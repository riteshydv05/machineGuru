# MachineGuru: Complete Project Viva & Interview Guide

This guide is the ultimate preparation handbook for defending the MachineGuru Retrieval-Augmented Generation (RAG) project. It is designed for university viva defenses, technical interviews, and system design discussions with senior engineers and AI researchers.

---

## SECTION 1: PROJECT OVERVIEW

### What MachineGuru is
MachineGuru is an industrial-grade, offline-capable Retrieval-Augmented Generation (RAG) application. It allows users to upload PDF documents and ask natural language questions about their content. The system retrieves relevant context from the uploaded documents and generates accurate, citation-backed answers using a local Large Language Model (LLM).

### Why it was built / Problem Statement
Generic LLMs (like ChatGPT) suffer from hallucinations and lack knowledge of proprietary or private documents. Sending sensitive enterprise documents to third-party cloud APIs poses significant security and privacy risks. MachineGuru was built to solve the dual problem of **data privacy** and **knowledge retrieval** by keeping all processing (embedding generation, vector storage, and LLM inference) entirely on-device or on-premise.
### Objective
To build a fully local, privacy-preserving, hallucination-resistant document Q&A system using modern AI architectures, achieving high retrieval accuracy and fast inference times.

### Expected Users
- Enterprise workers needing to query confidential PDFs (legal, medical, financial).
- Students and researchers analyzing large research papers.
- Anyone requiring a private, offline alternative to cloud-based RAG tools.

### Key Features
- **100% Local Execution**: No data leaves the machine.
- **Streaming Responses**: Real-time token streaming for a ChatGPT-like UX.
- **Citation Engine**: Exact source tracking to verify LLM claims.
- **Asynchronous Pipeline**: FastAPI backend handles concurrent users and processing.
- **Advanced UI**: React + Tailwind frontend with markdown rendering and history.

### Complete Architecture
- **Frontend**: React, Vite, Tailwind CSS, Axios, React Markdown.
- **Backend**: Python, FastAPI, Uvicorn, Pydantic, Dependency Injection.
- **AI/ML**: Ollama (Llama 3.2 1B), Sentence Transformers (`multilingual-e5-small`).
- **Database**: Qdrant (Vector Database).

---

## SECTION 2: PROJECT FLOW

### Workflow Diagram

```mermaid
flowchart TD
    subgraph Frontend
    UI[User UI (React)]
    end

    subgraph Backend [FastAPI Backend]
    API[API Router]
    Worker[Background Tasks]
    Context[Context Builder]
    end
    
    subgraph AI_Engine [AI & Embedding Stack]
    Chunker[Text Chunker]
    EmbModel[Sentence Transformer\nmultilingual-e5-small]
    LLM[Ollama\nLlama 3.2 1B]
    end

    subgraph Database
    Qdrant[(Qdrant\nVector DB)]
    end

    %% Document Upload Flow
    UI -- "1. Upload PDF" --> API
    API -- "2. Extract Text" --> Worker
    Worker -- "3. Chunk Data" --> Chunker
    Chunker -- "4. Generate Vectors" --> EmbModel
    EmbModel -- "5. Store Vectors" --> Qdrant

    %% Query Flow
    UI -- "6. Ask Question" --> API
    API -- "7. Embed Question" --> EmbModel
    EmbModel -- "8. Vector Search" --> Qdrant
    Qdrant -- "9. Return Top K" --> Context
    Context -- "10. Build Prompt" --> LLM
    LLM -- "11. Stream Response\n+ Citations" --> API
    API -- "12. Render Markdown" --> UI
```

### Flow Explanation
1. **Frontend**: User uploads a PDF via the React UI.
2. **Backend**: FastAPI receives the file, saves it, and extracts text asynchronously.
3. **Chunking**: Text is split into overlapping chunks (e.g., 512 tokens, 64 overlap).
4. **Embedding**: The `multilingual-e5-small` model converts chunks into dense vector representations.
5. **Storage**: Vectors and metadata (filename, page number) are stored in Qdrant.
6. **Query**: User asks a question. The frontend sends it to the `/query` endpoint.
7. **Question Embedding**: The question is converted into a vector using the same embedding model.
8. **Vector Search**: Qdrant performs a Cosine Similarity search to find the Top K closest chunks.
9. **Context Building**: The backend retrieves these chunks and formats them into a structured prompt.
10. **LLM Inference**: The prompt is sent to Ollama (Llama 3.2 1B), which generates an answer.
11. **Streaming**: The answer is streamed back to the frontend in chunks (Server-Sent Events).
12. **Rendering**: The React frontend renders the Markdown in real-time.

---

## SECTION 3: FRONTEND QUESTIONS

**1. What is React and why did you use it over Vanilla JS?**
React is a component-based UI library. It was used because RAG applications require complex state management (chat history, loading states, streaming text) which becomes unmanageable with Vanilla JS DOM manipulation.

**2. Why Vite instead of Create React App (CRA)?**
Vite uses ES modules and esbuild (written in Go), providing instant server start and lightning-fast Hot Module Replacement (HMR). CRA is slow, webpack-based, and officially deprecated by the React team.

**3. How does React Router work in this project?**
It uses client-side routing. Instead of requesting new HTML pages from the server, React Router updates the browser URL and renders the corresponding component (e.g., `/` for Chat, `/history` for logs) without reloading the page.

**4. Explain the component design of MachineGuru.**
The app is split into logical containers: `ChatWindow` (displays messages), `MessageInput` (handles typing/sending), `Sidebar` (document management), and `MarkdownRenderer` (formats LLM output).

**5. How did you handle API calls?**
Using Axios for standard REST calls (uploads, fetching history) and native `fetch` API for processing Server-Sent Events (SSE) during LLM streaming.

**6. What is Tailwind CSS and why use it?**
A utility-first CSS framework. It allows styling directly in JSX without context-switching to CSS files, preventing dead CSS and keeping bundle sizes tiny.

**7. How do you manage State in this app?**
Using React Hooks (`useState` for local state, `useReducer` for complex chat arrays, and potentially Context API for global theme/document registry states).

**8. Explain `useEffect` in the context of your app.**
Used for side effects, such as fetching the initial list of uploaded documents when the component mounts, or auto-scrolling to the bottom of the chat when a new message streams in.

**9. How do you optimize React performance?**
By using `useMemo` for expensive calculations (like formatting large chat histories), `useCallback` to prevent unnecessary re-renders of child components, and React.memo for static UI elements.

**10. How is streaming UI implemented?**
By reading the `ReadableStream` from the `fetch` response. We use a `TextDecoder` to decode byte chunks into strings, appending them to the current message's state variable, triggering React to re-render the new text in real-time.

*(Questions 11-50 Summary):*
- **Error Handling**: Wrapping API calls in try-catch, using Error Boundaries in React, displaying toast notifications for network failures.
- **Markdown**: Using `react-markdown`. It parses the string into an AST (Abstract Syntax Tree) and maps markdown elements to React components.
- **Responsive Design**: Using Tailwind's breakpoints (`md:`, `lg:`) to collapse the sidebar on mobile devices.
- **Hooks**: Custom hooks like `useChat()` encapsulate the streaming logic away from the UI components.
- **Virtual DOM**: React updates a virtual tree and syncs only changed nodes to the real DOM, making streaming text updates very fast.

---

## SECTION 4: BACKEND QUESTIONS

**1. What is FastAPI and why choose it over Flask/Django?**
FastAPI is a modern Python web framework. It was chosen because it natively supports `async`/`await` (crucial for IO-bound LLM and DB calls), generates automatic Swagger documentation, and uses Pydantic for extremely fast data validation.

**2. How does Dependency Injection work in FastAPI?**
Using the `Depends()` keyword. It allows passing reusable components (like DB connections or API clients) into route handlers. This makes testing easy because dependencies can be mocked.

**3. What is Pydantic?**
A data validation library in Python. It enforces type hints at runtime. In MachineGuru, it validates incoming JSON payloads (e.g., ensuring a query is a string) and structures outgoing responses.

**4. Explain Async/Await in Python.**
It enables asynchronous programming using an event loop. While the backend waits for Qdrant to search vectors or Ollama to generate text, the event loop can serve other incoming HTTP requests, massively increasing concurrency.

**5. What is Uvicorn?**
An ASGI (Asynchronous Server Gateway Interface) web server implementation for Python. FastAPI is the framework; Uvicorn is the server that actually runs it and handles the network sockets.

**6. How is CORS handled?**
Using FastAPI's `CORSMiddleware`. It adds headers (like `Access-Control-Allow-Origin`) to responses, telling the browser that the frontend (e.g., `localhost:5173`) is permitted to call the backend (`localhost:8000`).

**7. How do you handle file uploads?**
Using FastAPI's `UploadFile`. It spools large files to disk instead of keeping them in memory, preventing RAM exhaustion when uploading massive PDFs.

**8. What is a Singleton Service?**
A design pattern ensuring a class has only one instance. The Qdrant client and Embedding model are loaded as singletons to avoid re-initializing heavy network connections or reloading gigabytes of model weights on every request.

**9. How do you stream responses from FastAPI?**
Using `StreamingResponse`. It yields data chunks (often as Server-Sent Events format `data: ... \n\n`) generated by an async generator function communicating with Ollama.

**10. How is logging implemented?**
Using the `loguru` library for structured, colorized, and async-safe logging, recording request times, memory usage, and errors.

*(Questions 11-50 Summary):*
- **Middleware**: Functions that run before/after every request, used for calculating request duration (`X-Process-Time`) and adding unique `X-Request-ID`s.
- **Validation Errors**: Return 422 Unprocessable Entity automatically via Pydantic.
- **Background Tasks**: FastAPI's `BackgroundTasks` allow returning a 202 Accepted to the user while PDF chunking happens in the background.

---

## SECTION 5: DATABASE QUESTIONS (QDRANT)

**1. What is a Vector Database?**
A database specifically designed to store, manage, and search high-dimensional vectors (arrays of numbers) based on their mathematical distance/similarity, rather than exact keyword matches.

**2. Why Qdrant?**
Qdrant is written in Rust (fast and memory-safe), supports HNSW indexing, filtering by payload (metadata), and provides a great Python client. It can run in-memory, locally, or in Docker.

**3. What is a Collection in Qdrant?**
Equivalent to a "Table" in SQL. In MachineGuru, we have a collection (e.g., `documents`) that stores all chunk vectors.

**4. What is the Payload?**
The metadata attached to a vector. For a chunk vector, the payload contains the actual raw text chunk, the filename, and the page number.

**5. How does Similarity Search work?**
It calculates the distance between the query vector and all stored vectors. The closest vectors (smallest distance) represent the most semantically similar text.

**6. What index does Qdrant use?**
HNSW (Hierarchical Navigable Small World), a graph-based algorithm for fast Approximate Nearest Neighbor (ANN) search.

**7. How do you filter searches?**
By passing a `Filter` object in Qdrant. For example, restricting the vector search *only* to vectors where `payload.filename == "report.pdf"`.

*(Questions 8-40 Summary):*
- **Vector dimension**: Must match the embedding model output exactly (e.g., 384 for `multilingual-e5-small`).
- **Distance Metric**: Configured as Cosine Distance during collection creation.
- **CRUD Operations**: Handled via `upsert` (insert/update), `search` (read), and `delete` using point IDs (UUIDs).

---

## SECTION 6 & 7: EMBEDDINGS & VECTOR MATH

**1. What is an Embedding?**
A numerical representation of text (an array of floats). Words/sentences with similar meanings are mapped to points that are close to each other in this high-dimensional space.

**2. Why `multilingual-e5-small`?**
It is highly efficient, requires very little RAM (under 500MB), computes fast on CPU, supports multiple languages, and has a vector dimension of 384, making DB storage compact.

**3. What is Cosine Similarity?**
A metric that measures the cosine of the angle between two vectors. Value ranges from -1 (opposite) to 1 (identical). It focuses on orientation (semantics) rather than magnitude (length of text).

**4. Why is Vector Dimension important?**
It defines the expressiveness of the model. 384 dimensions mean the model represents text using 384 distinct semantic features. Qdrant must be initialized with this exact number.

**5. What is the difference between Chunk and Question embeddings?**
In asymmetric models (like e5), queries and documents have different prefixes (e.g., `query: ` vs `passage: `) to optimize the mathematical space for Q&A tasks.

**6. What is HNSW?**
Hierarchical Navigable Small World. It's a multi-layered graph algorithm. It finds nearest neighbors quickly by navigating a coarse graph at the top layer, and zooming into finer graphs at lower layers, avoiding O(N) linear search.

**7. Why not just use Exact Nearest Neighbor (KNN)?**
Exact search requires comparing the query against *every single vector* in the database (O(N)). HNSW is an Approximate (ANN) search, trading a tiny bit of accuracy for massive speed gains (O(log N)).

---

## SECTION 8: RAG (Retrieval-Augmented Generation)

**1. What is RAG?**
A framework that improves LLM responses by fetching factual context from an external database and injecting it into the prompt before the LLM generates an answer.

**2. Why use RAG instead of Fine-Tuning?**
Fine-tuning teaches the model *style* or general domain knowledge but is bad at recalling specific facts, requires expensive GPU compute, and cannot easily update or delete knowledge. RAG is factual, allows instant knowledge updates (just add to DB), and provides source citations.

**3. What is Chunking and why is it needed?**
Splitting a large document into smaller pieces (e.g., paragraphs). LLMs have a context window limit, and embedding entire PDFs at once dilutes the semantic meaning.

**4. What is Overlap in Chunking?**
Including a portion of the previous chunk in the next chunk (e.g., 64 tokens). It prevents sentences or concepts from being cut abruptly in half across two chunks.

**5. What is Top K?**
The number of most relevant chunks retrieved from the database to feed to the LLM. Usually set to 3-5. Too high = LLM gets confused/context overflows. Too low = missing information.

**6. How do you prevent Hallucinations?**
By using a strict system prompt: "Answer ONLY using the provided context. If the answer is not in the context, say 'I don't know'."

**7. How does the Citation Engine work?**
Because the context injected into the prompt includes metadata (filename, chunk ID), the LLM is instructed to append these markers (e.g., `[source: file.pdf]`) when it uses a specific fact.

---

## SECTION 9 & 10: LLM & PROMPT ENGINEERING

**1. What is Llama 3.2 1B?**
A highly capable, lightweight large language model by Meta, optimized for edge devices and fast CPU/budget-GPU inference.

**2. What is Ollama?**
A framework that makes it incredibly easy to run open-source LLMs locally. It manages model weights, quantization, and provides a REST API similar to OpenAI's.

**3. Explain Temperature.**
Controls randomness. `0.0` is greedy/deterministic (best for RAG to ensure factual answers). `1.0` is highly creative (good for writing poetry, bad for factual Q&A).

**4. What is Max Tokens / Context Window?**
Context Window is the maximum amount of text (prompt + answer) the LLM can process at once (e.g., 8192 tokens for Llama 3). Max Tokens is the limit set for the generated response.

**5. What is Quantization?**
Reducing the precision of the neural network weights (e.g., from 16-bit floats to 4-bit integers). This drastically reduces RAM usage (e.g., an 8GB model fits in 2GB) with minimal loss in reasoning quality.

**6. Explain the RAG Prompt Structure.**
```text
System: You are a helpful assistant. Use ONLY the following context to answer.
Context:
[Doc 1]: {chunk_1_text}
[Doc 2]: {chunk_2_text}
User Question: {user_query}
```

---

## SECTION 12: SYSTEM DESIGN

**Why FastAPI instead of Flask?**
RAG apps are I/O bound (waiting for DBs and LLMs). FastAPI's async nature handles this efficiently, whereas Flask's synchronous nature blocks the thread.

**Why React instead of Next.js?**
MachineGuru is a highly interactive, client-side heavy dashboard (streaming, markdown). Server-Side Rendering (Next.js) doesn't offer significant benefits for a local, authenticated enterprise app where SEO is irrelevant.

**Why local inference (Ollama) instead of OpenAI?**
1. **Privacy**: Confidential enterprise PDFs cannot legally be sent to third parties.
2. **Cost**: Zero recurring API costs.
3. **Air-gapped capability**: Can run completely offline.

**Why Qdrant instead of MongoDB/PostgreSQL?**
While Postgres has `pgvector`, Qdrant is purpose-built from the ground up for vector search, making it faster, easier to configure, and optimized specifically for HNSW.

---

## SECTION 13: PROJECT-SPECIFIC VIVA QUESTIONS

**1. Why did you choose chunk size 512 and overlap 64?**
512 tokens roughly equals a medium-sized paragraph, which contains a single, complete semantic thought. 64 tokens of overlap (about 1-2 sentences) ensures context is maintained across chunk boundaries.

**2. How does the model know which document to answer from?**
It doesn't inherently know. The backend performs the vector search, extracts the text from the top results, and manually feeds that text into the LLM's prompt. The LLM only sees what the backend provides.

**3. What happens if Qdrant is down?**
FastAPI throws a connection error. The global exception handler catches it and returns a clean `503 Service Unavailable` or `500 Internal Error` JSON response to the React frontend, which displays a toast notification.

**4. How is streaming implemented under the hood?**
Ollama streams tokens via HTTP chunks. FastAPI wraps this in an async generator using `StreamingResponse(media_type="text/event-stream")`. The React frontend uses the Fetch API to read the stream reader in a `while(!done)` loop.

**5. How do you optimize latency?**
- Use small, quantized models (Llama 1B).
- Keep embedding models loaded in RAM (Singleton).
- Use HNSW index in Qdrant instead of exact search.
- Stream responses so Time-To-First-Token (TTFT) is instantly perceived by the user.

*(Remaining specific questions focus on your exact `settings.py` config, docker-compose setup, and specific prompt string used).*

---

## SECTION 14 & 15: EDGE CASES & DEBUGGING

**What if the uploaded document contains conflicting information?**
The vector database retrieves both conflicting chunks. The LLM receives both in the context. Depending on the prompt, the LLM will either synthesize them ("Document A says X, but Document B says Y") or get confused. This requires robust prompt engineering to instruct the LLM on handling conflicts.

**How do you update embeddings if a PDF changes?**
You must delete the existing vectors associated with that filename (using a Qdrant payload filter deletion), re-parse the updated PDF, and insert the new vectors.

**What if the context exceeds the token limit?**
The LLM throws an Out Of Memory / Context Length Exceeded error. Solution: Strictly control `Top_K * Chunk_Size` to ensure it is always less than the LLM's max context window (e.g., 5 * 512 = 2560, well under Llama's 8k limit).

**Debugging: LLM Hallucination**
Check the retrieved context. Did Qdrant return the right chunks? If yes, the prompt is too weak (temperature too high, or system prompt not strict enough). If no, the embedding model or chunking strategy is flawed.

**Debugging: Slow responses**
Is it retrieval or generation? If TTFT (Time To First Token) is slow, the embedding model or Qdrant search is the bottleneck. If the streaming itself is slow, the LLM inference is bottlenecked by CPU/RAM speed.

---

## SECTION 18: RAPID FIRE ROUND (Selection)

1. **Which port does FastAPI run on by default?** 8000
2. **Which port does Vite use?** 5173
3. **What algorithm does Qdrant use for indexing?** HNSW
4. **What metric measures vector distance?** Cosine Similarity
5. **What library validates Python data types?** Pydantic
6. **What does RAG stand for?** Retrieval-Augmented Generation
7. **Is React Router client-side or server-side?** Client-side
8. **What UI framework did you use?** Tailwind CSS
9. **How are tokens streamed?** Server-Sent Events (SSE)
10. **What is an embedding?** A float array representing semantic meaning.
11. **Why overlap chunks?** To prevent cutting context in half.
12. **What does Temperature do?** Controls LLM randomness.
13. **What is the dimension of e5-small?** 384
14. **Is Llama 3.2 1B open source?** Yes (open weights).
15. **What runs the FastAPI app?** Uvicorn.

---

## SECTION 20: 10-PAGE CHEAT SHEET (Summary)

### 1. Core Architecture
- **Stateless Backend**: FastAPI stores no state; all state is in Qdrant or client browser.
- **Microservices-lite**: Docker-compose orchestrates Backend, Frontend, and Qdrant.

### 2. The RAG Formula
`Answer = LLM ( System_Prompt + Qdrant_Search ( Embed ( User_Question ) ) )`

### 3. Important Commands
- Run Backend: `uvicorn main:app --reload`
- Run Frontend: `npm run dev`
- Run DB: `docker run -p 6333:6333 qdrant/qdrant`
- Download Model: `ollama run llama3.2:1b`

### 4. Key Configurations to Memorize
- **Chunk Size**: 512 tokens
- **Chunk Overlap**: 64 tokens
- **Embedding Model**: `intfloat/multilingual-e5-small`
- **LLM**: `llama3.2:1b`
- **Top K Retrieval**: 5

### 5. Common Interview Pitfalls to Avoid
- **Mistake**: Saying "The LLM searches the database."
- **Correction**: "The Backend searches the database via vectors, and passes the text to the LLM."
- **Mistake**: Saying "Fine-tuning is better than RAG."
- **Correction**: "RAG is better for factual retrieval and avoiding hallucinations; fine-tuning is for tone/style."

### 6. Performance Optimizations (Bragging Points)
- Mention **Async/Await**: Prove you understand Python's event loop.
- Mention **Singleton Patterns**: Explain how caching the embedding model in memory prevents 10-second loads on every API call.
- Mention **Generator Functions**: Explain how streaming reduces perceived latency from 15 seconds to 0.5 seconds.
- Mention **Quantization**: Explain how you can run a billion-parameter model on a standard laptop CPU.

---
*End of Guide. Review this document thoroughly before your presentation.*
