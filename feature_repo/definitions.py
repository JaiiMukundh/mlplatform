"""Feast entities, feature views, and services (P6.2).

The offline source is the Parquet file published by the P6 setup Job to the
``feast-offline`` MinIO bucket; ``FEAST_S3_ENDPOINT_URL`` points Feast's S3
client at MinIO. The six features and their order match ``mlp_common.schemas``
and therefore the model's expected input order.
"""

from __future__ import annotations

from datetime import timedelta

from feast import Entity, FeatureService, FeatureView, Field, FileSource
from feast.types import Float32, Int64

customer = Entity(
    name="customer",
    join_keys=["customer_id"],
    description="Loan applicant.",
)

customer_features_source = FileSource(
    path="s3://feast-offline/customer_features.parquet",
    timestamp_field="event_timestamp",
)

customer_features = FeatureView(
    name="customer_features",
    entities=[customer],
    ttl=timedelta(days=365),
    schema=[
        Field(name="income", dtype=Float32),
        Field(name="debt_to_income", dtype=Float32),
        Field(name="credit_history_months", dtype=Float32),
        Field(name="num_late_payments_90d", dtype=Int64),
        Field(name="avg_monthly_balance", dtype=Float32),
        Field(name="utilization_ratio", dtype=Float32),
    ],
    online=True,
    source=customer_features_source,
)

loan_default_service = FeatureService(
    name="loan_default_v1",
    features=[customer_features],
)
