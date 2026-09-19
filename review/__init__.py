"""review - check a study package for disagreement between the SAP, the
datasets and the TLF outputs.

Piece A (this commit): dataset_reader and output_reader only. Everything
here is deterministic - no model calls, and nothing in this package writes
to the existing generators or to app.py.
"""
