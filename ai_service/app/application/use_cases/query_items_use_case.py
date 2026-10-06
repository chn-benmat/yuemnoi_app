from pydantic_core import PydanticCustomError
from typing import List, Optional

from app.application.prompts.catalog_guidance import SELECTION_PROMPT
from app.application.services.catalog_guidance import catalog_snapshot, generate_reviewed, validated_schema
from app.domain.entities.catalog_guidance import CatalogSelection, GuidancePolicy, SelectionPlan
from app.domain.entities.intent_decision import IntentDecision
from app.domain.entities.item import Item
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.llm_service import LLMServiceInterface
from app.domain.exceptions import GuidanceGenerationError


class QueryItemsUseCase:
    """Select catalog IDs semantically, then enforce verifiable numeric constraints."""

    def __init__(self, item_repository: ItemRepositoryInterface,
                 llm_service: LLMServiceInterface, policy: GuidancePolicy):
        self._item_repo = item_repository
        self._llm = llm_service
        self._policy = policy

    async def execute(self, decision: IntentDecision, limit: Optional[int] = None) -> List[Item]:
        return (await self.execute_selection(decision, limit)).items

    async def execute_selection(self, decision: IntentDecision,
                                limit: Optional[int] = None) -> CatalogSelection:
        limit = self._policy.max_items if limit is None else min(limit, self._policy.max_items)
        if limit < 1:
            raise PydanticCustomError("catalog_selection_limit_must_be_positive", "Selection limit must be positive")
        items = await self._item_repo.get_all_items(refresh=True)
        snapshot = catalog_snapshot(items)
        if not items:
            return CatalogSelection([], "no_matches", [], "", [], snapshot)
        id_map = {item.id: item for item in items}
        units = {item.type for item in items if item.type.strip()}

        def validate(plan: SelectionPlan):
            ids = [selected.id for selected in plan.selected_items]
            if len(ids) > limit or len(ids) != len(set(ids)) or not set(ids) <= set(id_map):
                raise PydanticCustomError("catalog_selected_catalog_ids_must_be_real__unique_and_within_limit", "Selected catalog IDs must be real, unique and within limit")
            if (plan.mode == "items") != bool(ids):
                raise PydanticCustomError("catalog_selection_mode_and_item_list_disagree", "Selection mode and item list disagree")
            if plan.mode == "categories" and not getattr(decision, "clarification_declined", False):
                raise PydanticCustomError("catalog_category_browsing_requires_a_declined_questionnaire", "Category browsing requires a declined questionnaire")
            requirement = plan.price_requirement
            if requirement is not None:
                if decision.budget_max is None or requirement.maximum != decision.budget_max:
                    raise PydanticCustomError("catalog_price_requirement_must_match_the_user_s_stated_ceiling", "Price requirement must match the user's stated ceiling")
                if decision.budget_unit is None or requirement.user_unit != decision.budget_unit:
                    raise PydanticCustomError("catalog_price_requirement_must_preserve_an_established_user_billing_period", "Price requirement must preserve an established user billing period")
                if not set(requirement.catalog_units) <= units:
                    raise PydanticCustomError("catalog_price_requirement_must_use_real_catalog_units", "Price requirement must use real catalog units")
            if ids and decision.budget_max is not None and requirement is None:
                raise PydanticCustomError("catalog_a_stated_budget_requires_a_verified_unit_interpretation", "A stated budget requires a verified unit interpretation")
            for item_id in ids:
                item = id_map[item_id]
                if plan.purpose == "recommendation" and not item.is_available:
                    raise PydanticCustomError("catalog_unavailable_items_cannot_be_recommendations", "Unavailable items cannot be recommendations")
                if requirement is not None:
                    if item.type not in requirement.catalog_units or item.price > requirement.maximum:
                        raise PydanticCustomError("catalog_selected_item_violates_price_or_billing_unit", "Selected item violates price or billing unit")

        plan = await generate_reviewed(self._llm, self._policy, {
            "task": "selection", "understanding": decision.model_dump(),
            "catalog": snapshot, "limit": limit,
        }, validated_schema(SelectionPlan, validate), SELECTION_PROMPT)
        # Re-read authoritative fields after generation/review. A changed source
        # invalidates the evidence instead of returning a stale price or stock flag.
        fresh_items = await self._item_repo.get_all_items(refresh=True)
        fresh_snapshot = catalog_snapshot(fresh_items)
        fresh_map = {item.id: item for item in fresh_items}
        fields = {"id", "name", "category", "price", "type", "status", "description"}
        for selected in plan.selected_items:
            if selected.id not in fresh_map or (
                id_map[selected.id].model_dump(include=fields) != fresh_map[selected.id].model_dump(include=fields)
            ):
                raise GuidanceGenerationError("catalog_changed")
        if plan.mode == "categories" and set(fresh_snapshot["categories"]) != set(snapshot["categories"]):
            raise GuidanceGenerationError("catalog_changed")
        if plan.mode == "no_matches" and (
            {item["id"]: item for item in snapshot["items"]} !=
            {item["id"]: item for item in fresh_snapshot["items"]}
        ):
            raise GuidanceGenerationError("catalog_changed")
        return CatalogSelection(
            items=[fresh_map[selected.id] for selected in plan.selected_items],
            mode=plan.mode, available_categories=fresh_snapshot["categories"] if plan.mode == "categories" else [],
            reasoning=plan.reasoning, selected_items=plan.selected_items, catalog_evidence=fresh_snapshot)

    async def refresh_selection(self, selection: CatalogSelection) -> CatalogSelection:
        """Revalidate evidence after answer synthesis, without reading answer text."""
        fresh = await self._item_repo.get_all_items(refresh=True)
        snapshot = catalog_snapshot(fresh)
        fresh_map = {item.id: item for item in fresh}
        fields = {"id", "name", "category", "price", "type", "status", "description"}
        for item in selection.items:
            if item.id not in fresh_map or item.model_dump(include=fields) != fresh_map[item.id].model_dump(include=fields):
                raise GuidanceGenerationError("catalog_changed")
        if selection.mode == "categories" and set(selection.available_categories) != set(snapshot["categories"]):
            raise GuidanceGenerationError("catalog_changed")
        if selection.mode == "no_matches" and (
            selection.catalog_evidence is None or
            {i["id"]: i for i in selection.catalog_evidence["items"]} != {i["id"]: i for i in snapshot["items"]}
        ):
            raise GuidanceGenerationError("catalog_changed")
        return CatalogSelection([fresh_map[i.id] for i in selection.items], selection.mode,
            selection.available_categories, selection.reasoning, selection.selected_items, snapshot)

    def validate_selection(self, plan: SelectionPlan, decision, items: List[Item]):
        """Pure source checks for the combined selection/answer call."""
        id_map = {item.id: item for item in items}
        ids = [selected.id for selected in plan.selected_items]
        if len(ids) > self._policy.max_items or len(ids) != len(set(ids)) or not set(ids) <= set(id_map):
            raise PydanticCustomError("catalog_invalid_selection_ids", "Invalid selection IDs")
        if (plan.mode == "items") != bool(ids):
            raise PydanticCustomError("catalog_selection_mode_disagrees_with_ids", "Selection mode disagrees with IDs")
        if decision.catalog_operation == "selection" and plan.purpose != "recommendation":
            raise PydanticCustomError("catalog_a_recommendation_cannot_bypass_availability_checks", "A recommendation cannot bypass availability checks")
        if set(ids) & set(decision.excluded_items):
            raise PydanticCustomError("catalog_selected_an_explicitly_excluded_id", "Selected an explicitly excluded ID")
        requirement = plan.price_requirement
        if requirement is not None:
            if decision.budget_max is None or requirement.maximum != decision.budget_max:
                raise PydanticCustomError("catalog_budget_ceiling_changed", "Budget ceiling changed")
            if decision.budget_unit is None or requirement.user_unit != decision.budget_unit:
                raise PydanticCustomError("catalog_unknown_or_changed_budget_period", "Unknown or changed budget period")
            if not set(requirement.catalog_units) <= {item.type for item in items}:
                raise PydanticCustomError("catalog_unknown_catalog_period", "Unknown catalog period")
            if set(requirement.catalog_units) != {decision.budget_unit}:
                raise PydanticCustomError("catalog_a_price_period_conversion_requires_authoritative_conversion_evidence", "A price period conversion requires authoritative conversion evidence")
        if ids and decision.budget_max is not None and requirement is None:
            raise PydanticCustomError("catalog_budget_requires_an_established_unit_interpretation", "Budget requires an established unit interpretation")
        for item_id in ids:
            item = id_map[item_id]
            if plan.purpose == "recommendation" and not item.is_available:
                raise PydanticCustomError("catalog_unavailable_recommendation", "Unavailable recommendation")
            if requirement and (item.type not in requirement.catalog_units or item.price > requirement.maximum):
                raise PydanticCustomError("catalog_budget_violation", "Budget violation")

    def selection_from_snapshot(self, plan: SelectionPlan, decision, items: List[Item]):
        self.validate_selection(plan, decision, items)
        snapshot = catalog_snapshot(items)
        return CatalogSelection([i for selected in plan.selected_items for i in items if i.id == selected.id],
            plan.mode, snapshot["categories"] if plan.mode == "categories" else [],
            plan.reasoning, plan.selected_items, snapshot)

    async def materialize_selection(self, plan: SelectionPlan, decision, items: List[Item]):
        selection = self.selection_from_snapshot(plan, decision, items)
        return await self.refresh_selection(selection)
