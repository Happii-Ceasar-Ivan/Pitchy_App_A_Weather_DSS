# RAG Knowledge Base

`manifest.yaml` (committed) lists the approved documents: key (a `rules.yaml` source id), title,
authority, version, source and the sections to load. The text files `<key>.txt` are **git-ignored**
(copyrighted manuals); the user saves them here on their PC. Do not fabricate source text.

Text file format: UTF-8; each section starts with a line `# section: <name>`, where `<name>` is
exactly one of the manifest's sections for that document. The loader refuses a file that is
missing, has an unknown section, or lacks one.

Load from `backend/` on the PC (admin URL from the root `.env`, never printed):

    uv run python scripts/load_protocol_documents.py --dry-run           # parse and count only
    uv run python scripts/load_protocol_documents.py                     # load as draft
    uv run python scripts/load_protocol_documents.py --approve           # load and approve
    uv run python scripts/load_protocol_documents.py --only fifa_ecm_2022

Search (`services/rag/retrieval`) returns only documents with `approval_status = 'approved'`.
