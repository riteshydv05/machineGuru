# 🎬 MachineGuru — Demo Video Script
**Target Duration:** 2:30 – 3:00 minutes  
**Tone:** Professional, confident, enthusiastic  
**Audience:** Professors / Evaluators / Technical Reviewers

---

## 🕐 [0:00 – 0:20] — OPENING HOOK (20 sec)

**[Screen: Blank / Title Slide or just your face on camera]**

> **NARRATION:**
> "What if you could ask your machine manual a question — and get an instant, accurate answer — without sending a single byte of data to the cloud?"
>
> "That's exactly what MachineGuru does. It's a fully offline, AI-powered document assistant built for industrial and enterprise environments."
>
> "Let me show you how it works."

---

## 🕐 [0:20 – 0:45] — PROBLEM + SOLUTION (25 sec)

**[Screen: Dashboard Page — `http://localhost:5173`]**

> **NARRATION:**
> "Traditional AI tools like ChatGPT are powerful, but they have two major problems in real-world enterprise settings —"
>
> "First: they don't know your private documents. Second: sending confidential data to the cloud is a security risk."
>
> "MachineGuru solves both. It runs a full RAG pipeline — Retrieval-Augmented Generation — completely on your local machine, or on an NVIDIA Jetson edge device. No internet required. No data leaks. Ever."

---

## 🕐 [0:45 – 1:20] — UPLOADING A DOCUMENT (35 sec)

**[Screen: Navigate to Upload Page]**

> **ACTION:** Click on the **Upload** tab in the sidebar.

> **NARRATION:**
> "Let me walk you through the core workflow. I'll start by uploading a PDF — let's say a machine maintenance manual."

> **ACTION:** Drag and drop a PDF file (e.g., `motor_manual.pdf`) into the upload area, or click to browse and select it.

> **NARRATION:**
> "When you upload a document, here's what happens under the hood:"
>
> "The backend — built with FastAPI — extracts the raw text, splits it into overlapping chunks of around 512 tokens, and runs each chunk through a local embedding model called `multilingual-e5-small`."
>
> "These vector embeddings are then stored in Qdrant — a high-performance local vector database."

> **ACTION:** Show the upload progress / success confirmation on screen.

> **NARRATION:**
> "And just like that — the document is ready to be queried. Zero cloud calls made."

---

## 🕐 [1:20 – 2:10] — ASKING A QUESTION (50 sec)

**[Screen: Navigate to Chat Page]**

> **ACTION:** Click on the **Chat** tab in the sidebar.

> **NARRATION:**
> "Now comes the magic. I'll type a natural language question about the document I just uploaded."

> **ACTION:** Type a question in the chat input — e.g.:  
> `"What is the recommended maintenance interval for the motor bearings?"`

> **ACTION:** Hit Enter / click Send.

> **NARRATION:**
> "Watch what happens. The system first converts my question into a vector using the same embedding model. It then performs a cosine similarity search in Qdrant to find the top-K most relevant chunks from the document."
>
> "Those chunks are assembled into a structured prompt, which is passed to Ollama running Llama 3.2 locally."
>
> "And then — the answer streams back in real time."

> **[Watch the response stream in token by token on the Chat Page]**

> **NARRATION:**
> "You can see the answer appearing live — just like ChatGPT — but this is running 100% on your machine."
>
> "And notice here — the response includes **source citations**, showing exactly which page and document the answer came from. No hallucinations. No guesswork."

---

## 🕐 [2:10 – 2:35] — DOCUMENTS & HISTORY (25 sec)

**[Screen: Navigate to Documents Page, then History Page]**

> **NARRATION:**
> "The Documents page shows all uploaded files — you can view, manage, and delete them anytime."

> **ACTION:** Quickly scroll through the Documents page.

> **ACTION:** Click on the **History** tab.

> **NARRATION:**
> "And the History page keeps a full log of every query and answer — so you can revisit past conversations without re-querying."

---

## 🕐 [2:35 – 3:00] — CLOSING (25 sec)

**[Screen: Back to Dashboard — show the stats / health indicators]**

> **NARRATION:**
> "MachineGuru is built on a clean architecture — FastAPI backend, React frontend, Qdrant vector DB, and Ollama for local LLM inference."
>
> "It's designed to run on edge hardware like the NVIDIA Jetson Orin, with full CUDA GPU acceleration — making it practical for real factory floors and industrial environments."
>
> "Completely offline. Completely private. And completely production-ready."
>
> "Thank you."

---

## 📋 PRE-RECORDING CHECKLIST

| Item | Status |
|------|--------|
| App is running (`./start.sh`) | ☐ |
| A sample PDF is ready to upload | ☐ |
| Browser is at `http://localhost:5173` | ☐ |
| Screen resolution set (1080p recommended) | ☐ |
| Microphone levels tested | ☐ |
| Notifications / DND mode enabled | ☐ |
| Browser bookmarks bar hidden (clean look) | ☐ |

---

## 💡 FILMING TIPS

- **Speak slowly and clearly** — technical demos need pace control.
- **Pause briefly** after each major action to let the viewer absorb it.
- **Don't rush the streaming response** — let it finish naturally, it's visually impressive.
- **Keep mouse movements smooth** — avoid erratic cursor jumps.
- Re-record sections individually if needed and edit in post.
