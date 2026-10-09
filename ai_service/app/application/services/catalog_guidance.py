import json
from decimal import Decimal
from typing import Callable, List, Type, TypeVar

from pydantic import BaseModel, ValidationError, create_model, model_validator

from app.application.prompts.catalog_guidance import REVIEW_PROMPT
from app.domain.entities.catalog_guidance import GuidancePolicy, GuidanceReview
from app.domain.entities.item import Item
from app.domain.exceptions import GuidanceGenerationError
from app.domain.interfaces.llm_service import LLMServiceInterface

T = TypeVar("T", bound=BaseModel)


def catalog_snapshot(items: List[Item]) -> dict:
    ids = [item.id for item in items]
    if any(not item_id.strip() for item_id in ids) or len(ids) != len(set(ids)):
        raise GuidanceGenerationError("invalid_catalog_ids")
    if any(not item.name.strip() or not item.category.strip() or not item.type.strip() for item in items):
        raise GuidanceGenerationError("incomplete_catalog_fields")
    return {
        "items": [item.model_dump(include={"id", "name", "category", "price", "type", "status", "description"})
                  for item in items],
        "categories": list(dict.fromkeys(item.category for item in items if item.category.strip())),
    }


def presented_record(item, presentation=None):
    record = item.model_dump()
    if presentation:
        amount = format(Decimal(str(item.price)).normalize(), presentation['amount_format'])
        period = presentation['unit_labels'].get(item.type, item.type)
        record.update(unit_display=period, status_display=presentation['status_labels'].get(item.status, item.status),
            price_display=presentation['price_template'].format(amount=amount, currency=presentation['currency'], period=period))
    return record


def presented_catalog(snapshot, items, presentation):
    records = {i.id: presented_record(i, presentation) for i in items}
    return {**snapshot, 'items': [{**row, **{k: v for k, v in records[row['id']].items() if k.endswith('_display')}} for row in snapshot['items']]}


def compact_catalog(snapshot: dict) -> dict:
    """Lossless column/row transport, preserving every authoritative field."""
    columns = ["id", "name", "category", "price", "type", "status", "description"]
    columns += [key for key in ('price_display', 'unit_display', 'status_display') if any(key in item for item in snapshot['items'])]
    return {"columns": columns, "rows": [[item[key] for key in columns] for item in snapshot["items"]],
            "categories": snapshot["categories"]}


def validated_schema(base: Type[T], validate: Callable[[T], None]) -> Type[T]:
    # Runtime constraints are checked inside provider decoding, so the existing
    # cascade tries a backup provider for an invalid output rather than heuristics.
    def check(self):
        validate(self)
        return self
    return create_model(f"Validated{base.__name__}", __base__=base,
                        __validators__={"runtime_contract": model_validator(mode="after")(check)})


async def generate_reviewed(llm: LLMServiceInterface, policy: GuidancePolicy,
                            payload: dict, schema: Type[T], instruction: str,
                            review_instruction: str = REVIEW_PROMPT) -> T:
    rejection = []
    for _ in range(policy.generation_attempts):
        candidate_payload = {**payload, "previous_validation_issues": rejection}
        candidate = await llm.generate_structured(
            prompt=json.dumps(candidate_payload, ensure_ascii=False), schema=schema,
            system_instruction=instruction, temperature=policy.temperature)
        try:
            # Also enforce the contract on third-party adapters returning models
            # without applying the supplied schema.
            candidate = schema.model_validate(candidate.model_dump())
        except (ValidationError, ValueError):
            rejection = ["structured_contract_violation"]
            continue
        review_payload = {**payload, "candidate": candidate.model_dump()}
        if "approved_knowledge" in payload:
            cited_ids = set(candidate.knowledge_ids)
            review_payload["approved_knowledge"] = [article for article in payload["approved_knowledge"] if article["id"] in cited_ids]
        review = await llm.generate_structured(
            prompt=json.dumps(review_payload, ensure_ascii=False),
            schema=GuidanceReview, system_instruction=review_instruction,
            temperature=policy.temperature)
        review = GuidanceReview.model_validate(review.model_dump())
        if review.approved and not review.issues:
            return candidate
        rejection = review.issues or ["semantic_review_rejected"]
    raise GuidanceGenerationError("generation_rejected")
