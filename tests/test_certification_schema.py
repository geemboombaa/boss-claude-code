"""Tests for .boss/schemas/certification.schema.json"""
import json
import pathlib
import pytest

try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

SCHEMA_PATH = pathlib.Path(__file__).parent.parent / ".boss" / "schemas" / "certification.schema.json"


@pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
class TestCertificationSchema:

    @pytest.fixture
    def schema(self):
        return json.loads(SCHEMA_PATH.read_text())

    def valid_cert(self, **overrides):
        base = {
            "certified": True,
            "certifier": "Agent 3",
            "timestamp": "2026-05-05T12:00:00Z",
            "spec_file": ".boss/spec.md",
            "verification_file": ".boss/verification.md",
            "requirements_total": 3,
            "requirements_passed": 3,
            "requirements_failed": 0,
            "requirements_met": ["REQ-001", "REQ-002", "REQ-003"],
            "gaps": [],
            "proof_artifacts": [".boss/test-results/stdout.txt"]
        }
        base.update(overrides)
        return base

    def test_valid_certified_passes(self, schema):
        jsonschema.validate(self.valid_cert(), schema)

    def test_certified_true_requires_no_gaps(self, schema):
        cert = self.valid_cert(certified=True, gaps=[{"requirement": "REQ-001", "reason": "failed"}], requirements_failed=1)
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(cert, schema)

    def test_certified_false_with_gaps_valid(self, schema):
        cert = self.valid_cert(
            certified=False,
            requirements_passed=2,
            requirements_failed=1,
            gaps=[{"requirement": "REQ-003", "reason": "test failed"}]
        )
        jsonschema.validate(cert, schema)

    def test_missing_required_field_fails(self, schema):
        cert = self.valid_cert()
        del cert["certified"]
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(cert, schema)

    def test_negative_requirements_fail(self, schema):
        cert = self.valid_cert(requirements_total=-1)
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(cert, schema)

    def test_gap_requires_requirement_and_reason(self, schema):
        cert = self.valid_cert(
            certified=False,
            requirements_failed=1,
            gaps=[{"requirement": "REQ-001"}]  # missing reason
        )
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(cert, schema)
