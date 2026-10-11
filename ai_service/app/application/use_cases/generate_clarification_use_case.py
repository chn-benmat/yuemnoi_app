from typing import List

from app.application.prompts.catalog_guidance import QUESTIONNAIRE_PROMPT
from app.application.services.catalog_guidance import catalog_snapshot, generate_reviewed, validated_schema
from app.domain.entities.catalog_guidance import GuidancePolicy, QuestionnairePlan
from app.domain.entities.clarification import ClarificationQuestion, ChoiceOption, QuestionStep
from app.domain.entities.intent_decision import IntentDecision
from app.domain.interfaces.item_repository import ItemRepositoryInterface
from app.domain.interfaces.llm_service import LLMServiceInterface


class GenerateClarificationUseCase:
    """Ask only necessary unknowns with choices grounded in this catalog snapshot."""

    def __init__(self, llm_service: LLMServiceInterface,
                 item_repository: ItemRepositoryInterface, policy: GuidancePolicy):
        self._llm = llm_service
        self._item_repo = item_repository
        self._policy = policy

    async def execute(self, user_message: str, decision: IntentDecision) -> ClarificationQuestion:
        if getattr(decision, "clarification_declined", False):
            raise ValueError("Clarification was declined")
        snapshot = catalog_snapshot(await self._item_repo.get_all_items(refresh=True))
        missing = set(decision.missing_slots)
        known = {fact.dimension for fact in [*getattr(decision, "known_facts", []),
                                             *getattr(decision, "user_constraints", [])]}
        item_ids = {item["id"] for item in snapshot["items"]}

        def validate(plan: QuestionnairePlan):
            if not 1 <= len(plan.questions) <= self._policy.max_questions:
                raise ValueError("Question count outside configured bounds")
            question_ids = [question.id for question in plan.questions]
            dimensions = [question.dimension for question in plan.questions]
            if len(set(question_ids)) != len(question_ids) or len(set(dimensions)) != len(dimensions):
                raise ValueError("Question IDs and dimensions must be unique")
            if not set(dimensions) <= missing or set(dimensions) & known:
                raise ValueError("Questions must address unknown material dimension IDs")
            for question in plan.questions:
                if len(question.title) > self._policy.title_max_characters:
                    raise ValueError("Question title exceeds configured UI limit")
                if not 1 <= len(question.choices) <= self._policy.max_options:
                    raise ValueError("Choice count outside configured bounds")
                policy = self._policy.choice_policy
                if policy is not None:
                    minimum, maximum = ((policy.budget_total, policy.budget_total) if question.dimension == 'budget_max'
                                        else (policy.regular_min, policy.regular_max))
                    if not minimum <= len(question.choices) <= maximum:
                        raise ValueError('Choice count violates the questionnaire policy')
                ids = [choice.id for choice in question.choices]
                labels = [choice.label for choice in question.choices]
                if len(ids) != len(set(ids)) or len(labels) != len(set(labels)):
                    raise ValueError("Choice IDs and labels must be unique within the question")
                for choice in question.choices:
                    if len(choice.label) > self._policy.option_max_characters:
                        raise ValueError("Choice label exceeds configured UI limit")
                    if not set(choice.supporting_item_ids) <= item_ids:
                        raise ValueError("Choice cites unknown catalog IDs")

        plan = await generate_reviewed(self._llm, self._policy, {
            "task": "questionnaire", "user_message": user_message,
            "understanding": decision.model_dump(), "catalog": snapshot,
            "limits": {"max_questions": self._policy.max_questions,
                       "max_options": self._policy.max_options,
                       "choice_policy": self._policy.choice_policy.model_dump() if self._policy.choice_policy else None,
                       "title_max_characters": self._policy.title_max_characters,
                       "option_max_characters": self._policy.option_max_characters},
        }, validated_schema(QuestionnairePlan, validate), QUESTIONNAIRE_PROMPT)
        questions: List[QuestionStep] = []
        for index, question in enumerate(plan.questions):
            choices = [ChoiceOption(id=choice.id, label=choice.label, action_value=choice.value)
                       for choice in question.choices]
            questions.append(QuestionStep(id=question.id, title=question.title,
                dimension=question.dimension, choices=choices,
                options=[choice.label for choice in question.choices],
                step=index + 1, total_steps=len(plan.questions)))
        return ClarificationQuestion(question=plan.introduction,
            missing_dimension=plan.questions[0].dimension,
            options=questions[0].choices, questions=questions)
