"""Feast entities, feature views, and services (P6.2).

The offline source is the Parquet file published by the P6 setup Job to the
``feast-offline`` MinIO bucket; ``FEAST_S3_ENDPOINT_URL`` points Feast's S3
client at MinIO. The six features and their order match ``mlp_common.schemas``
and therefore the model's expected input order.
"""

from __future__ import annotations

import os
from datetime import timedelta

from feast import Entity, FeatureService, FeatureView, Field, FileSource, ValueType
from feast.types import Float32, Int64

customer = Entity(
    name="customer",
    join_keys=["customer_id"],
    value_type=ValueType.INT64,
    description="Loan applicant.",
)

# Feast 0.66 takes the endpoint override on the source itself (it does not read
# FEAST_S3_ENDPOINT_URL for FileSource); the env var carries the MinIO URL into
# the Feast Jobs. Credentials come from AWS_ACCESS_KEY_ID/SECRET on the pod.
customer_features_source = FileSource(
    path="s3://feast-offline/customer_features.parquet",
    timestamp_field="event_timestamp",
    s3_endpoint_override=os.environ.get("FEAST_S3_ENDPOINT_URL", ""),
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
