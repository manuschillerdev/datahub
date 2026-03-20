"""Tests for break_circular_refs — the iterative DFS that stubs circular
$ref chains in OpenAPI specs before resolution."""

import json

from datahub.ingestion.source.openapi_parser import break_circular_refs


def test_self_referencing_schema():
    """A schema that references itself (Employee.manager → Employee)."""
    spec = {
        "components": {
            "schemas": {
                "Employee": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "manager": {"$ref": "#/components/schemas/Employee"},
                    },
                }
            }
        }
    }
    break_circular_refs(spec)
    manager = spec["components"]["schemas"]["Employee"]["properties"]["manager"]
    assert "$ref" not in manager
    assert manager["type"] == "object"
    assert manager["x-circular-ref"] == "#/components/schemas/Employee"


def test_mutual_cycle():
    """A → B → A cycle."""
    spec = {
        "components": {
            "schemas": {
                "A": {
                    "type": "object",
                    "properties": {"b": {"$ref": "#/components/schemas/B"}},
                },
                "B": {
                    "type": "object",
                    "properties": {"a": {"$ref": "#/components/schemas/A"}},
                },
            }
        }
    }
    break_circular_refs(spec)
    # One of the back-edges should be stubbed, not both
    a_ref = spec["components"]["schemas"]["A"]["properties"]["b"]
    b_ref = spec["components"]["schemas"]["B"]["properties"]["a"]
    stubbed = "x-circular-ref" in a_ref or "x-circular-ref" in b_ref
    assert stubbed, "At least one back-edge should be stubbed"
    # The spec should be serializable (no cycles)
    json.dumps(spec)


def test_non_circular_refs_preserved():
    """Non-circular $refs must not be stubbed."""
    spec = {
        "components": {
            "schemas": {
                "Order": {
                    "type": "object",
                    "properties": {
                        "customer": {"$ref": "#/components/schemas/Customer"},
                    },
                },
                "Customer": {
                    "type": "object",
                    "properties": {"name": {"type": "string"}},
                },
            }
        }
    }
    break_circular_refs(spec)
    ref = spec["components"]["schemas"]["Order"]["properties"]["customer"]
    assert ref == {"$ref": "#/components/schemas/Customer"}


def test_deep_cycle():
    """A → B → C → A — the back-edge from C to A should be stubbed."""
    spec = {
        "components": {
            "schemas": {
                "A": {
                    "type": "object",
                    "properties": {"b": {"$ref": "#/components/schemas/B"}},
                },
                "B": {
                    "type": "object",
                    "properties": {"c": {"$ref": "#/components/schemas/C"}},
                },
                "C": {
                    "type": "object",
                    "properties": {"a": {"$ref": "#/components/schemas/A"}},
                },
            }
        }
    }
    break_circular_refs(spec)
    c_to_a = spec["components"]["schemas"]["C"]["properties"]["a"]
    assert "x-circular-ref" in c_to_a
    assert c_to_a["x-circular-ref"] == "#/components/schemas/A"
    # A→B and B→C should still be $refs
    assert "$ref" in spec["components"]["schemas"]["A"]["properties"]["b"]
    assert "$ref" in spec["components"]["schemas"]["B"]["properties"]["c"]


def test_swagger_v2_definitions():
    """Works with Swagger 2.x #/definitions/ prefix."""
    spec = {
        "definitions": {
            "Node": {
                "type": "object",
                "properties": {
                    "value": {"type": "integer"},
                    "child": {"$ref": "#/definitions/Node"},
                },
            }
        }
    }
    break_circular_refs(spec)
    child = spec["definitions"]["Node"]["properties"]["child"]
    assert "x-circular-ref" in child
    assert child["x-circular-ref"] == "#/definitions/Node"


def test_no_definitions():
    """Specs without definitions should not crash."""
    spec = {"openapi": "3.0.0", "paths": {}}
    break_circular_refs(spec)  # should be a no-op


def test_idempotent():
    """Running break_circular_refs twice produces the same result."""
    spec = {
        "components": {
            "schemas": {
                "Node": {
                    "type": "object",
                    "properties": {
                        "next": {"$ref": "#/components/schemas/Node"},
                    },
                }
            }
        }
    }
    break_circular_refs(spec)
    first = json.dumps(spec, sort_keys=True)
    break_circular_refs(spec)
    second = json.dumps(spec, sort_keys=True)
    assert first == second
