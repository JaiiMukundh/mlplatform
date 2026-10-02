"""Pydantic schemas shared by the serving API and its clients."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

CustomerId = Annotated[int, Field(ge=0)]
Probability = Annotated[float, Field(ge=0.0, le=1.0)]

MODEL_FEATURES = [
    "income",
    "debt_to_income",
    "credit_history_months",
    "num_late_payments_90d",
    "avg_monthly_balance",
    "utilization_ratio",
]


class StrictSchema(BaseModel):
    """Base schema that rejects misspelled or unexpected fields."""

    model_config = ConfigDict(extra="forbid")


class PredictRequest(StrictSchema):
    """Batch prediction request for between one and one hundred customers."""

    customer_ids: Annotated[list[CustomerId], Field(min_length=1, max_length=100)]


class Prediction(StrictSchema):
    """One customer's default probability and thresholded label."""

    customer_id: CustomerId
    default_probability: Probability
    label: Literal[0, 1]


class PredictResponse(StrictSchema):
    """Successful batch prediction response."""

    request_id: str
    model_version: str
    predictions: list[Prediction]


class UnknownCustomersError(StrictSchema):
    """Error body returned when any requested customer is unavailable."""

    error: Literal["unknown_customers"] = "unknown_customers"
    ids: list[CustomerId]


class HealthResponse(StrictSchema):
    """Liveness or readiness state."""

    status: Literal["ok", "not_ready"]


class ModelInfo(StrictSchema):
    """Metadata about the immutable model loaded by one API pod."""

    name: str
    version: str
    source: str
    loaded_at: datetime
    features: list[str]
