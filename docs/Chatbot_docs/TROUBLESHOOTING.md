# Troubleshooting

## Table of Contents
1. [Chatbot won't start](#chatbot-wont-start)
2. [503 — Cannot reach Julia server](#503--cannot-reach-julia-server)
3. [504 — Julia server timeout](#504--julia-server-timeout)
4. [Bedrock errors](#bedrock-errors)
5. [Config validation errors](#config-validation-errors)
6. [Session issues](#session-issues)
7. [FAQs](#faqs)

---

## Chatbot won't start

**Symptom:** `uvicorn` fails on import or startup.

**Fixes:**
- Confirm dependencies are installed: `pip install -r chatbot/requirements.txt`
- Check Python version is 3.9+: `python --version`
- On Windows, the `asyncio.WindowsProactorEventLoopPolicy` is set automatically in `app.py`. If you see asyncio-related errors, ensure you're running with the standard CPython interpreter (not a custom asyncio patch).

---

## 503 — Cannot reach Julia server

**Symptom:** Chat returns `"Cannot reach Julia pipeline server at port 8080."`

**Fix:** Start the Julia server first:
```bash
julia start_server.jl
```
Wait for the `HTTP server listening` message before sending a simulation. The first load takes 1–2 minutes.

---

## 504 — Julia server timeout

**Symptom:** Chat returns a 504 error after a Confirm & Run.

The Julia pipeline has a 30-second timeout from the FastAPI side. This is typically hit when:
- The Julia server is still loading TNCodebase on first start
- A very large system (N = 14, full spectrum) is taking longer than expected

**Fix:** Wait for Julia to finish loading, then retry. If the issue persists with N = 14, try enabling `use_sparse: true` in the algorithm config (edit the JSON manually in the config panel before confirming).

---

## Bedrock errors

**Symptom:** Chat returns `"Bedrock error: ..."` or HTTP 502.

| Error message | Cause | Fix |
|--------------|-------|-----|
| `AccessDeniedException` | Credentials missing or model not enabled | Check `~/.aws/credentials`; enable Claude Haiku in the Bedrock console (us-east-1) |
| `ValidationException` | Malformed request (shouldn't occur normally) | Check that `SESSIONS` history hasn't been corrupted; restart chatbot server |
| `ThrottlingException` | API rate limit hit | Wait a moment and retry |
| Credential chain errors | No valid AWS credentials found | Set `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, or configure `~/.aws/credentials` |

> The model ID is hardcoded to `us-east-1`. Requests to other regions will fail — make sure your Bedrock model access is enabled in `us-east-1` specifically.

---

## Config validation errors

**Symptom:** After editing the JSON manually and clicking Save, an error banner appears.

The Save button runs `JSON.parse()` on the textarea content. The error message shows the parse failure location. Common mistakes:
- Trailing comma after the last key in an object
- Missing quotes around string values
- Mismatched braces

Fix the JSON and click Save again. Click Discard to revert to the last valid config.

---

## Session issues

**Symptom:** Conversation history is lost after a page refresh, or the chatbot seems to have forgotten context.

- Session history is **in-memory** — it is lost when the chatbot server (`uvicorn`) restarts.
- The session ID is stored in `localStorage` under `tn_ed_session`. If the server restarted, the ID is stale and a new session will be created on your next message.
- To force a fresh session: open DevTools → Application → Local Storage → delete `tn_ed_session`, then refresh.

---

## FAQs

**Can I run DMRG or TDVP through the chatbot?**
No. The chatbot is scoped to ED (`ed_spectrum` and `ed_time_evolution`). DMRG and TDVP are available through direct Julia usage. See the [TN docs](../TN_docs/) for tensor network usage.

**Why is N limited to 14?**
ED stores the full Hilbert space as a dense matrix. For spin-1/2, that's 2^N states — at N = 14 the Hamiltonian is 16384 × 16384 (~2 GB for `ComplexF64`). Beyond N = 14 the memory and compute cost becomes impractical. Use DMRG for larger systems.

**Can I run multiple simulations in parallel?**
Each session has one active simulation at a time (input is locked while polling). Opening a second browser tab creates an independent session and can run concurrently, but the Julia server processes requests serially.

**The chatbot proposed a config I don't like. Do I have to start over?**
No — click Cancel, then describe the change in chat (e.g. "change N to 8"). Claude will build an updated config. Alternatively, use the Edit button for small numerical changes without restarting the conversation.

**Why does Claude sometimes skip asking about `S` or `dtype`?**
These are fixed defaults (`S=0.5`, `dtype="ComplexF64"`) and the system prompt instructs Claude not to ask about them unless the user explicitly specifies otherwise. If you need a different spin magnitude, mention it (e.g. "spin-1 chain") and Claude will include it.
