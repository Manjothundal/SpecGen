import { useState } from "react";

const phases = [
  {
    id: "0-4",
    name: "Core Pipeline",
    status: "complete",
    description: "Spec parser, prompt builder, generator, three-agent pipeline (Writer/Improver/Reviewer), config-driven modes",
    files: ["spec_parser.py", "assembler.py", "prompt_builder.py", "generator.py", "config.py", "reviewer.py", "improver.py", "runlog.py"],
    inputs: ["adam_spec.xlsx"],
    outputs: ["adsl.sas", "runlog.csv"],
    details: [
      "spec_parser.py reads ADaM spec Excel, routes variables by Source column",
      "prompt_builder.py builds LLM prompt per variable with macro catalog lookup",
      "generator.py runs Writer (local Ollama or API) then Improver/Reviewer (API)",
      "assembler.py wraps every block in BEGIN/END markers, handles MACRO_SIDE_EFFECTS",
      "Three modes: Offline (Ollama only), Hybrid (Ollama write + API review), Full API",
    ],
  },
  {
    id: "4.5",
    name: "Macro Catalog + RAG",
    status: "complete",
    description: "Macro catalog with 15 variable-level rows, exact match + agentic pattern classification",
    files: ["macro_lookup.py", "macro_catalog.csv", "macros/"],
    inputs: ["macro_catalog.csv"],
    outputs: ["SAS macro calls in generated code"],
    details: [
      "macro_catalog.csv: 15 rows with pattern, purpose, exact call per variable",
      "find_macro(): exact variable name match against catalog",
      "find_by_pattern(): Claude classifies derivation pattern, suggests matching macro",
      "7 validated SAS macros: agegr, trtvar, dtctodt, popflag, studyday, bmigrp, existflag",
      "Side-effect dedup: AGEGR1N, TRT01PN auto-skipped when parent macro handles them",
    ],
  },
  {
    id: "5a",
    name: "aCRF Parser",
    status: "complete",
    description: "Parse annotated CRF PDFs — extract blue SDTM annotations, codelists, qualifiers",
    files: ["acrf_parser.py", "build_sample_acrf.py", "sample_acrf.pdf"],
    inputs: ["aCRF PDF (annotated CRF)"],
    outputs: ["acrf_metadata.xlsx"],
    details: [
      "Splits PDF chars by color: blue = SDTM annotations, black = CRF labels",
      "Regex matches DOMAIN.VARIABLE patterns (including SUPP-- domains)",
      "Associates each annotation with nearest CRF field label on same row",
      "Captures codelist hints and test code qualifiers (VSTESTCD=SYSBP)",
      "8-page sample aCRF: 104 fields across 18 domains (12 standard + 6 SUPP)",
    ],
  },
  {
    id: "5b",
    name: "SDTM Spec Builder",
    status: "complete",
    description: "Build draft SDTM spec from reviewed aCRF metadata with structural variables per domain class",
    files: ["sdtm_spec_builder.py"],
    inputs: ["acrf_metadata.xlsx (reviewed)"],
    outputs: ["sdtm_spec_draft.xlsx"],
    details: [
      "Adds CDISC structural vars: STUDYID, USUBJID, DOMAIN, --SEQ per domain",
      "Handles 5 domain classes: DM, Events, Interventions, Findings, Findings About Events",
      "SUPP-- domains get fixed template: RDOMAIN, IDVAR, IDVARVAL, QNAM, QLABEL, QVAL, QORIG, QEVAL",
      "Claude API enrichment fills proper CDISC labels, types, lengths",
      "Offline fallback infers metadata from SDTM naming conventions",
    ],
  },
  {
    id: "5d",
    name: "Protocol Parser",
    status: "complete",
    description: "Extract trial design metadata (TA, TE, TV, TI, TS) from protocol PDFs",
    files: ["protocol_parser.py", "build_sample_protocol.py", "sample_protocol.pdf"],
    inputs: ["Protocol PDF"],
    outputs: ["protocol_metadata.xlsx"],
    details: [
      "TS: Trial Summary — sponsor, phase, indication, endpoints (16 parameters)",
      "TA: Trial Arms — arm codes, descriptions, element sequences",
      "TE: Trial Elements — screening, treatment, follow-up with durations/epochs",
      "TV: Trial Visits — visit numbers, names, target days, windows",
      "TI: Inclusion/Exclusion — all I/E criteria with codes",
    ],
  },
  {
    id: "6",
    name: "Spec Differ + Patcher",
    status: "complete",
    description: "Compare spec versions, patch existing SAS programs with changes",
    files: ["spec_differ.py", "spec_patcher.py", "test_differ.py", "test_patcher.py"],
    inputs: ["adam_spec.xlsx (v1)", "adam_spec_v2.xlsx (v2)", "adsl.sas (v1)"],
    outputs: ["adsl_v2.sas (patched)"],
    details: [
      "spec_differ.py compares v1 vs v2 spec workbooks",
      "Returns new/changed/deleted/unchanged variable lists",
      "spec_patcher.py uses BEGIN/END markers to replace changed blocks",
      "Appends new variables, rebuilds KEEP list",
      "Patch runs now logged to runlog.csv",
    ],
  },
  {
    id: "5c",
    name: "SDTM Program Generation",
    status: "next",
    description: "New multi-row assembly mode that reads SDTM spec and generates SAS programs per domain",
    files: ["sdtm_assembler.py (planned)"],
    inputs: ["sdtm_spec_draft.xlsx"],
    outputs: ["dm.sas, ae.sas, vs.sas, ..."],
    details: [
      "Multi-row assembly for BDS-like structures (one row per test per visit)",
      "Domain-class-aware code generation (Events vs Findings vs Interventions)",
      "SUPP-- dataset generation from QNAM/QVAL spec",
      "SE/SV derivation from subject data + trial design (TE/TV)",
    ],
  },
  {
    id: "future",
    name: "ADaM BDS Domains",
    status: "planned",
    description: "Extend ADaM pipeline beyond ADSL to BDS datasets: ADAE, ADVS, ADLB, ADCM, ADEFF",
    files: ["(planned)"],
    inputs: ["ADaM BDS specs"],
    outputs: ["adae.sas, advs.sas, adlb.sas, ..."],
    details: [
      "PARAMCD/PARAM mapping, baseline derivation (BASE, CHG, PCHG)",
      "Analysis flags (ANL01FL), visit windowing",
      "New BDS macros for macro catalog",
    ],
  },
];

const domainData = {
  standard: [
    { code: "DM", name: "Demographics", class: "Special Purpose", source: "aCRF", vars: 24 },
    { code: "AE", name: "Adverse Events", class: "Events", source: "aCRF", vars: 17 },
    { code: "CM", name: "Concomitant Meds", class: "Interventions", source: "aCRF", vars: 19 },
    { code: "VS", name: "Vital Signs", class: "Findings", source: "aCRF", vars: 16 },
    { code: "EX", name: "Exposure", class: "Interventions", source: "aCRF", vars: 10 },
    { code: "DS", name: "Disposition", class: "Events", source: "aCRF", vars: 14 },
    { code: "MH", name: "Medical History", class: "Events", source: "aCRF", vars: 14 },
    { code: "DV", name: "Protocol Deviations", class: "Events", source: "aCRF", vars: 14 },
    { code: "EG", name: "ECG", class: "Findings", source: "aCRF", vars: 16 },
    { code: "TU", name: "Tumor Identification", class: "Findings About Events", source: "aCRF", vars: 14 },
    { code: "TR", name: "Tumor Results", class: "Findings About Events", source: "aCRF", vars: 14 },
    { code: "RS", name: "Disease Response", class: "Findings About Events", source: "aCRF", vars: 14 },
  ],
  supp: [
    { code: "SUPPAE", parent: "AE", vars: 14 },
    { code: "SUPPCM", parent: "CM", vars: 12 },
    { code: "SUPPDM", parent: "DM", vars: 13 },
    { code: "SUPPEG", parent: "EG", vars: 11 },
    { code: "SUPPRS", parent: "RS", vars: 13 },
    { code: "SUPPVS", parent: "VS", vars: 13 },
  ],
  trial: [
    { code: "TS", name: "Trial Summary", source: "Protocol", records: 16 },
    { code: "TA", name: "Trial Arms", source: "Protocol", records: 3 },
    { code: "TE", name: "Trial Elements", source: "Protocol", records: 5 },
    { code: "TV", name: "Trial Visits", source: "Protocol", records: 15 },
    { code: "TI", name: "Inclusion/Exclusion", source: "Protocol", records: 22 },
  ],
};

const flowSteps = [
  { icon: "📄", label: "aCRF PDF", desc: "Annotated CRF with blue SDTM mappings", color: "#3B82F6" },
  { icon: "🔍", label: "acrf_parser.py", desc: "Extract blue annotations by color", color: "#8B5CF6" },
  { icon: "📊", label: "acrf_metadata.xlsx", desc: "104 fields, 18 domains — human reviews", color: "#10B981" },
  { icon: "🏗️", label: "sdtm_spec_builder.py", desc: "Add structural vars + Claude enrichment", color: "#8B5CF6" },
  { icon: "📋", label: "sdtm_spec_draft.xlsx", desc: "289 variables, one sheet per domain", color: "#10B981" },
  { icon: "⚡", label: "sdtm_assembler.py", desc: "Generate SAS programs (Phase 5c)", color: "#F59E0B" },
  { icon: "💾", label: "dm.sas, ae.sas, ...", desc: "Production SDTM programs", color: "#EF4444" },
];

const protocolFlow = [
  { icon: "📄", label: "Protocol PDF", desc: "Study design, visits, I/E criteria", color: "#3B82F6" },
  { icon: "🔍", label: "protocol_parser.py", desc: "Regex + Claude API extraction", color: "#8B5CF6" },
  { icon: "📊", label: "protocol_metadata.xlsx", desc: "TS, TA, TE, TV, TI — human reviews", color: "#10B981" },
  { icon: "⚡", label: "Trial design datasets", desc: "Generate TA, TE, TV, TI, TS programs", color: "#F59E0B" },
];

const techStack = [
  { name: "Python 3.13", role: "Core language" },
  { name: "Anaconda", role: "Environment" },
  { name: "Claude API", role: "Writer/Improver/Reviewer agents + enrichment" },
  { name: "Ollama", role: "Local LLM for offline mode" },
  { name: "pdfplumber", role: "PDF text + color extraction" },
  { name: "openpyxl", role: "Excel read/write" },
  { name: "reportlab", role: "Sample PDF generation" },
  { name: "VS Code", role: "IDE" },
];

const StatusBadge = ({ status }) => {
  const styles = {
    complete: "bg-emerald-100 text-emerald-800 border-emerald-300",
    next: "bg-amber-100 text-amber-800 border-amber-300",
    planned: "bg-slate-100 text-slate-600 border-slate-300",
  };
  const labels = { complete: "Complete", next: "Next Up", planned: "Planned" };
  return (
    <span className={`text-xs font-semibold px-2.5 py-0.5 rounded-full border ${styles[status]}`}>
      {labels[status]}
    </span>
  );
};

const PhaseCard = ({ phase, isExpanded, onClick }) => {
  const borderColor = phase.status === "complete" ? "border-emerald-400" : phase.status === "next" ? "border-amber-400" : "border-slate-300";
  return (
    <div
      className={`bg-white rounded-xl border-2 ${borderColor} cursor-pointer transition-all duration-200 hover:shadow-lg`}
      onClick={onClick}
    >
      <div className="p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span className="text-sm font-mono font-bold text-slate-500">Phase {phase.id}</span>
            <StatusBadge status={phase.status} />
          </div>
          <span className="text-slate-400 text-lg">{isExpanded ? "−" : "+"}</span>
        </div>
        <h3 className="font-bold text-slate-900 text-lg">{phase.name}</h3>
        <p className="text-slate-600 text-sm mt-1">{phase.description}</p>
      </div>
      {isExpanded && (
        <div className="border-t border-slate-100 p-4 bg-slate-50 rounded-b-xl">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
            <div>
              <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Files</h4>
              <div className="flex flex-wrap gap-1">
                {phase.files.map((f) => (
                  <span key={f} className="text-xs bg-blue-50 text-blue-700 px-2 py-0.5 rounded font-mono">{f}</span>
                ))}
              </div>
            </div>
            <div>
              <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Input</h4>
              <div className="flex flex-wrap gap-1">
                {phase.inputs.map((f) => (
                  <span key={f} className="text-xs bg-green-50 text-green-700 px-2 py-0.5 rounded font-mono">{f}</span>
                ))}
              </div>
            </div>
            <div>
              <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Output</h4>
              <div className="flex flex-wrap gap-1">
                {phase.outputs.map((f) => (
                  <span key={f} className="text-xs bg-orange-50 text-orange-700 px-2 py-0.5 rounded font-mono">{f}</span>
                ))}
              </div>
            </div>
          </div>
          <div>
            <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">How it works</h4>
            <ul className="space-y-1">
              {phase.details.map((d, i) => (
                <li key={i} className="text-sm text-slate-700 flex items-start gap-2">
                  <span className="text-emerald-500 mt-0.5">▸</span>
                  <span>{d}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  );
};

const FlowDiagram = ({ steps, title }) => (
  <div className="mb-8">
    <h3 className="text-lg font-bold text-slate-800 mb-4">{title}</h3>
    <div className="flex flex-wrap items-center gap-2 justify-center">
      {steps.map((step, i) => (
        <div key={i} className="flex items-center gap-2">
          <div className="bg-white rounded-xl border-2 p-3 text-center min-w-[140px] shadow-sm" style={{ borderColor: step.color }}>
            <div className="text-2xl mb-1">{step.icon}</div>
            <div className="font-bold text-sm text-slate-800">{step.label}</div>
            <div className="text-xs text-slate-500 mt-1">{step.desc}</div>
          </div>
          {i < steps.length - 1 && <span className="text-slate-400 text-xl font-bold">→</span>}
        </div>
      ))}
    </div>
  </div>
);

const DomainTable = () => (
  <div className="space-y-6">
    <div>
      <h3 className="text-lg font-bold text-slate-800 mb-3">Standard Domains (from aCRF)</h3>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-slate-800 text-white">
              <th className="px-3 py-2 text-left rounded-tl-lg">Domain</th>
              <th className="px-3 py-2 text-left">Name</th>
              <th className="px-3 py-2 text-left">Class</th>
              <th className="px-3 py-2 text-center rounded-tr-lg">Variables</th>
            </tr>
          </thead>
          <tbody>
            {domainData.standard.map((d, i) => (
              <tr key={d.code} className={i % 2 === 0 ? "bg-blue-50" : "bg-white"}>
                <td className="px-3 py-1.5 font-mono font-bold text-blue-700">{d.code}</td>
                <td className="px-3 py-1.5">{d.name}</td>
                <td className="px-3 py-1.5 text-slate-600">{d.class}</td>
                <td className="px-3 py-1.5 text-center">{d.vars}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <h3 className="text-lg font-bold text-slate-800 mb-3">SUPP Domains</h3>
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-emerald-700 text-white">
              <th className="px-3 py-2 text-left rounded-tl-lg">Domain</th>
              <th className="px-3 py-2 text-left">Parent</th>
              <th className="px-3 py-2 text-center rounded-tr-lg">Variables</th>
            </tr>
          </thead>
          <tbody>
            {domainData.supp.map((d, i) => (
              <tr key={d.code} className={i % 2 === 0 ? "bg-green-50" : "bg-white"}>
                <td className="px-3 py-1.5 font-mono font-bold text-emerald-700">{d.code}</td>
                <td className="px-3 py-1.5">{d.parent}</td>
                <td className="px-3 py-1.5 text-center">{d.vars}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div>
        <h3 className="text-lg font-bold text-slate-800 mb-3">Trial Design (from Protocol)</h3>
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-amber-600 text-white">
              <th className="px-3 py-2 text-left rounded-tl-lg">Domain</th>
              <th className="px-3 py-2 text-left">Name</th>
              <th className="px-3 py-2 text-center rounded-tr-lg">Records</th>
            </tr>
          </thead>
          <tbody>
            {domainData.trial.map((d, i) => (
              <tr key={d.code} className={i % 2 === 0 ? "bg-amber-50" : "bg-white"}>
                <td className="px-3 py-1.5 font-mono font-bold text-amber-700">{d.code}</td>
                <td className="px-3 py-1.5">{d.name}</td>
                <td className="px-3 py-1.5 text-center">{d.records}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  </div>
);

const tabs = [
  { id: "showcase", label: "Overview" },
  { id: "pipeline", label: "Pipeline" },
  { id: "demo", label: "Data Flow" },
  { id: "domains", label: "Domains" },
];

export default function SpecGenApp() {
  const [activeTab, setActiveTab] = useState("showcase");
  const [expandedPhase, setExpandedPhase] = useState(null);

  const completedCount = phases.filter((p) => p.status === "complete").length;
  const totalDomains = domainData.standard.length + domainData.supp.length + domainData.trial.length;
  const totalVars = domainData.standard.reduce((s, d) => s + d.vars, 0)
    + domainData.supp.reduce((s, d) => s + d.vars, 0);

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50">
      {/* Hero */}
      <div className="bg-gradient-to-r from-slate-900 via-slate-800 to-blue-900 text-white">
        <div className="max-w-5xl mx-auto px-6 py-10">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 bg-blue-500 rounded-lg flex items-center justify-center text-xl font-bold">S</div>
            <h1 className="text-4xl font-black tracking-tight">SpecGen</h1>
          </div>
          <p className="text-blue-200 text-lg mt-2 max-w-2xl">
            AI-powered clinical SAS program generator. From annotated CRFs and protocols to production-ready SDTM/ADaM programs — offline-first, audit-logged, three-agent pipeline.
          </p>
          <div className="flex flex-wrap gap-6 mt-6">
            <div className="bg-white/10 backdrop-blur rounded-lg px-4 py-3 text-center">
              <div className="text-3xl font-black">{completedCount}/{phases.length}</div>
              <div className="text-xs text-blue-300 uppercase tracking-wider">Phases Done</div>
            </div>
            <div className="bg-white/10 backdrop-blur rounded-lg px-4 py-3 text-center">
              <div className="text-3xl font-black">{totalDomains}</div>
              <div className="text-xs text-blue-300 uppercase tracking-wider">SDTM Domains</div>
            </div>
            <div className="bg-white/10 backdrop-blur rounded-lg px-4 py-3 text-center">
              <div className="text-3xl font-black">{totalVars}</div>
              <div className="text-xs text-blue-300 uppercase tracking-wider">Spec Variables</div>
            </div>
            <div className="bg-white/10 backdrop-blur rounded-lg px-4 py-3 text-center">
              <div className="text-3xl font-black">3</div>
              <div className="text-xs text-blue-300 uppercase tracking-wider">AI Agents</div>
            </div>
          </div>
          <div className="flex flex-wrap gap-2 mt-5">
            {techStack.map((t) => (
              <span key={t.name} className="text-xs bg-white/10 text-blue-200 px-2.5 py-1 rounded-full">
                {t.name}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="sticky top-0 z-10 bg-white/90 backdrop-blur border-b border-slate-200">
        <div className="max-w-5xl mx-auto px-6">
          <div className="flex gap-1">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-5 py-3 text-sm font-semibold transition-colors border-b-2 ${
                  activeTab === tab.id
                    ? "border-blue-600 text-blue-700 bg-blue-50/50"
                    : "border-transparent text-slate-500 hover:text-slate-700"
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-5xl mx-auto px-6 py-8">
        {activeTab === "showcase" && (
          <div className="space-y-8">
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <h2 className="text-2xl font-bold text-slate-900 mb-4">What is SpecGen?</h2>
              <p className="text-slate-700 leading-relaxed mb-4">
                SpecGen automates clinical SAS programming by reading study documents (annotated CRFs and protocols) and generating production-quality SAS programs. Instead of manually writing hundreds of lines of data step code per domain, a clinical programmer reviews the AI-generated output and corrects where needed.
              </p>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-blue-50 rounded-xl p-4 border border-blue-100">
                  <div className="text-2xl mb-2">📄 → 💻</div>
                  <h3 className="font-bold text-slate-800">Spec to Code</h3>
                  <p className="text-sm text-slate-600 mt-1">ADaM/SDTM specifications go in, validated SAS programs come out</p>
                </div>
                <div className="bg-purple-50 rounded-xl p-4 border border-purple-100">
                  <div className="text-2xl mb-2">🤖 × 3</div>
                  <h3 className="font-bold text-slate-800">Three-Agent Pipeline</h3>
                  <p className="text-sm text-slate-600 mt-1">Writer drafts, Improver refines, Reviewer validates — like a real programming team</p>
                </div>
                <div className="bg-emerald-50 rounded-xl p-4 border border-emerald-100">
                  <div className="text-2xl mb-2">🔒</div>
                  <h3 className="font-bold text-slate-800">Offline-First</h3>
                  <p className="text-sm text-slate-600 mt-1">Runs locally with Ollama for pharma environments with no cloud access</p>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <h2 className="text-2xl font-bold text-slate-900 mb-4">Architecture</h2>
              <div className="bg-slate-900 rounded-xl p-5 font-mono text-sm text-slate-300 overflow-x-auto">
                <pre>{`┌─────────────────────────────────────────────────────────────┐
│                      SpecGen Pipeline                       │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   INPUTS     │   PARSERS    │   BUILDERS   │   OUTPUTS      │
├──────────────┼──────────────┼──────────────┼────────────────┤
│ aCRF PDF     │→ acrf_parser │→ spec_builder│→ sdtm_spec.xlsx│
│ Protocol PDF │→ proto_parser│→ trial_design│→ proto_meta.xlsx│
│ ADaM Spec    │→ spec_parser │→ assembler   │→ adsl.sas      │
├──────────────┼──────────────┴──────────────┼────────────────┤
│              │    THREE-AGENT PIPELINE      │                │
│              │  ┌────────┐  ┌──────────┐   │                │
│ macro_catalog│→ │ WRITER │→ │ IMPROVER │   │                │
│ macro_lookup │  └────────┘  └──────────┘   │                │
│              │       ↕           ↕          │                │
│ config.py    │  ┌──────────────────────┐   │                │
│ (mode select)│  │     REVIEWER         │   │  runlog.csv    │
│              │  └──────────────────────┘   │  (audit trail) │
├──────────────┼─────────────────────────────┼────────────────┤
│  AMENDMENT   │  spec_differ → spec_patcher │→ adsl_v2.sas   │
│  v1 vs v2    │  (marker-based patching)    │  (patched)     │
└──────────────┴─────────────────────────────┴────────────────┘`}</pre>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <h2 className="text-2xl font-bold text-slate-900 mb-4">GitHub</h2>
              <a href="https://github.com/Manjothundal/specgen" target="_blank" rel="noopener noreferrer"
                 className="inline-flex items-center gap-2 bg-slate-900 text-white px-5 py-2.5 rounded-lg font-semibold hover:bg-slate-700 transition-colors">
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/></svg>
                Manjothundal/specgen
              </a>
            </div>
          </div>
        )}

        {activeTab === "pipeline" && (
          <div className="space-y-4">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-2xl font-bold text-slate-900">Development Phases</h2>
              <div className="flex items-center gap-3 text-sm">
                <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-full bg-emerald-400 inline-block"></span> Complete</span>
                <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-full bg-amber-400 inline-block"></span> Next</span>
                <span className="flex items-center gap-1"><span className="w-3 h-3 rounded-full bg-slate-300 inline-block"></span> Planned</span>
              </div>
            </div>
            {phases.map((phase) => (
              <PhaseCard
                key={phase.id}
                phase={phase}
                isExpanded={expandedPhase === phase.id}
                onClick={() => setExpandedPhase(expandedPhase === phase.id ? null : phase.id)}
              />
            ))}
          </div>
        )}

        {activeTab === "demo" && (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold text-slate-900">Data Flow</h2>
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <FlowDiagram steps={flowSteps} title="aCRF → SDTM Programs" />
            </div>
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <FlowDiagram steps={protocolFlow} title="Protocol → Trial Design Datasets" />
            </div>
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <h3 className="text-lg font-bold text-slate-800 mb-4">ADaM Pipeline (existing)</h3>
              <div className="flex flex-wrap items-center gap-2 justify-center">
                {[
                  { icon: "📊", label: "adam_spec.xlsx", desc: "25-63 variable spec", color: "#3B82F6" },
                  { icon: "🔍", label: "spec_parser.py", desc: "Route by Source column", color: "#8B5CF6" },
                  { icon: "🤖", label: "Writer → Improver → Reviewer", desc: "Three-agent pipeline", color: "#8B5CF6" },
                  { icon: "💾", label: "adsl.sas", desc: "Production program", color: "#EF4444" },
                ].map((step, i, arr) => (
                  <div key={i} className="flex items-center gap-2">
                    <div className="bg-white rounded-xl border-2 p-3 text-center min-w-[140px] shadow-sm" style={{ borderColor: step.color }}>
                      <div className="text-2xl mb-1">{step.icon}</div>
                      <div className="font-bold text-sm text-slate-800">{step.label}</div>
                      <div className="text-xs text-slate-500 mt-1">{step.desc}</div>
                    </div>
                    {i < arr.length - 1 && <span className="text-slate-400 text-xl font-bold">→</span>}
                  </div>
                ))}
              </div>
            </div>
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <h3 className="text-lg font-bold text-slate-800 mb-4">Amendment Patching</h3>
              <div className="flex flex-wrap items-center gap-2 justify-center">
                {[
                  { icon: "📊", label: "v1 vs v2 spec", desc: "spec_differ.py", color: "#3B82F6" },
                  { icon: "🔀", label: "New / Changed / Deleted", desc: "Variable-level diff", color: "#F59E0B" },
                  { icon: "🔧", label: "spec_patcher.py", desc: "BEGIN/END marker replacement", color: "#8B5CF6" },
                  { icon: "💾", label: "adsl_v2.sas", desc: "Patched program", color: "#EF4444" },
                ].map((step, i, arr) => (
                  <div key={i} className="flex items-center gap-2">
                    <div className="bg-white rounded-xl border-2 p-3 text-center min-w-[140px] shadow-sm" style={{ borderColor: step.color }}>
                      <div className="text-2xl mb-1">{step.icon}</div>
                      <div className="font-bold text-sm text-slate-800">{step.label}</div>
                      <div className="text-xs text-slate-500 mt-1">{step.desc}</div>
                    </div>
                    {i < arr.length - 1 && <span className="text-slate-400 text-xl font-bold">→</span>}
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {activeTab === "domains" && (
          <div>
            <h2 className="text-2xl font-bold text-slate-900 mb-6">SDTM Domain Coverage</h2>
            <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
              <DomainTable />
            </div>
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="border-t border-slate-200 bg-white mt-12">
        <div className="max-w-5xl mx-auto px-6 py-4 text-center text-sm text-slate-500">
          SpecGen — Built with Python, Claude API, and clinical programming expertise
        </div>
      </div>
    </div>
  );
}
