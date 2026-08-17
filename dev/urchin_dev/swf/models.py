# msgspec-backed models + loaders for the ffdec/AMF runtime dumps in
# dev/data_json/. The dumps wrap every AS value in one
# of three shapes, modeled here as msgspec Structs (tagged on "type"):
#
#   {"type": "EcmaArray", "denseValues": {...}, "associativeValues": {...}}
#   {"type": "Object",    "members": {...}}
#   {"type": "Undefined"}
#
# msgspec.json.decode is the fast path (the buffs/items dumps are multi-MB);
# load_json() decodes any file to plain python containers, while the typed
# helpers below unwrap the AMF shapes without isinstance-noise at call sites.
from __future__ import annotations

from pathlib import Path
from typing import Any

import msgspec


class EcmaArray(msgspec.Struct, tag_field="type", tag="EcmaArray"):
    denseValues: dict[str, Any] = {}
    associativeValues: dict[str, Any] = {}

    def as_list(self) -> list[Any]:
        """denseValues keyed '0'..'n' -> ordered list."""
        return [self.denseValues[k] for k in sorted(self.denseValues, key=int)]

    def as_dict(self) -> dict[int, Any]:
        return {int(k): v for k, v in self.denseValues.items()}


class AmfObject(msgspec.Struct, tag_field="type", tag="Object"):
    members: dict[str, Any] = {}


class Undefined(msgspec.Struct, tag_field="type", tag="Undefined"):
    pass


type AmfValue = EcmaArray | AmfObject | Undefined


def load_json(path: str | Path) -> Any:
    """Fast whole-file decode to plain python containers."""
    return msgspec.json.decode(Path(path).read_bytes())


def load_amf(path: str | Path) -> AmfValue:
    """Decode a file whose top level is one AMF wrapper."""
    return msgspec.json.decode(Path(path).read_bytes(), type=AmfValue)


# --- unwrap helpers for plain-container dumps (load_json output) -----------


def dense_values(node: Any) -> dict[str, Any]:
    """The denseValues of an EcmaArray node (plain dict form)."""
    if isinstance(node, dict) and node.get("type") == "EcmaArray":
        return node.get("denseValues", {})
    return {}


def dense_list(node: Any) -> list[Any]:
    dense = dense_values(node)
    return [dense[k] for k in sorted(dense, key=int)]


def members(node: Any) -> dict[str, Any]:
    """The members of an Object node (plain dict form)."""
    if isinstance(node, dict) and node.get("type") == "Object":
        return node.get("members", {})
    if isinstance(node, dict) and "members" in node:
        return node["members"]
    return {}


def coerce_num(value: Any, default: float = 0.0) -> float:
    """Numbers in the dump can be {'type': 'Undefined'} - coerce those."""
    if isinstance(value, (int, float)):
        return float(value)
    return default


def coerce_text(value: Any, default: str = "") -> str:
    if isinstance(value, str):
        return value
    return default
