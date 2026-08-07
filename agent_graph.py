"""agent_graph.py — Writer -> Improver -> Reviewer as a LangGraph state graph.

Same logic as the inline chain it replaced, in spec_patcher._build_block's
non-macro-match branch: draft the block, rewrite it to sign-off quality,
QC it, and prepend a QC FLAG comment if the Reviewer fails it. Restructured
as an explicit graph (nodes + edges) instead of straight-line Python — the
one place in the app that still auto-chains all three steps end to end
(Generate itself is Writer-only/on-demand since Piece 10 in ROADMAP.md, for
per-click responsiveness; the full chain still runs here because
patch_program's changed/new-variable paths and the "Insert" legacy-program
path need a complete, reviewed block in one call, with no user in the loop
between steps).

draft --> improve --> review --(FAIL)--> flag --> END
                          \\--(PASS)---------------> END
"""

from typing import Optional, TypedDict

from langgraph.graph import END, StateGraph

from assembler import clean, gen_block
from improver import improve_block
from reviewer import review_block


class BlockState(TypedDict):
    row: object                    # pandas Series — the spec row for this variable
    known_vars: list
    language: str
    writer_mode: Optional[str]
    reviewer_mode: Optional[str]
    ig_version: Optional[str]
    code: str
    verdict: Optional[str]


def _draft(state: BlockState) -> dict:
    code = gen_block(state["row"], language=state["language"], writer_mode=state["writer_mode"])
    return {"code": code}


def _improve(state: BlockState) -> dict:
    improved = improve_block(
        state["code"], state["row"], state["known_vars"],
        language=state["language"], mode=state["reviewer_mode"], ig_version=state["ig_version"],
    )
    return {"code": clean(improved)}


def _review(state: BlockState) -> dict:
    verdict = review_block(
        state["code"], state["known_vars"],
        language=state["language"], mode=state["reviewer_mode"], ig_version=state["ig_version"],
    )
    return {"verdict": verdict}


def _flag(state: BlockState) -> dict:
    return {"code": f'/* QC FLAG: {state["verdict"]} */\n{state["code"]}'}


def _route_after_review(state: BlockState) -> str:
    return "flag" if (state["verdict"] or "").startswith("FAIL") else END


def _build_graph():
    graph = StateGraph(BlockState)
    graph.add_node("draft", _draft)
    graph.add_node("improve", _improve)
    graph.add_node("review", _review)
    graph.add_node("flag", _flag)
    graph.set_entry_point("draft")
    graph.add_edge("draft", "improve")
    graph.add_edge("improve", "review")
    graph.add_conditional_edges("review", _route_after_review, {"flag": "flag", END: END})
    graph.add_edge("flag", END)
    return graph.compile()


# Compiled once per process — the graph itself is stateless (all per-call
# data lives in the state dict passed to .invoke()), so it's reused across
# every block the same way `catalog = load_catalog()` is reused elsewhere.
_GRAPH = _build_graph()


def run_pipeline(row, known_vars, language="sas", writer_mode=None, reviewer_mode=None, ig_version=None):
    """Run the Writer -> Improver -> Reviewer graph for one variable's block.

    Returns the final code: QC-flag-prepended on a Reviewer FAIL, unchanged
    on PASS — the same contract as the inline chain this replaced.
    """
    result = _GRAPH.invoke({
        "row": row,
        "known_vars": known_vars,
        "language": language,
        "writer_mode": writer_mode,
        "reviewer_mode": reviewer_mode,
        "ig_version": ig_version,
        "code": "",
        "verdict": None,
    })
    return result["code"]
