# Agent Note: Session routing headers on every LLM adapter

Status: implemented

English | [中文](2026-09-14-opencode-session-routing-headers.zh.md)

## Problem

OpenCode Go rejects chat requests that carry no session with `400 MissingSessionID` (`Request is missing x-opencode-session`). The harness sent its native `x-deepseek-harness-session-id` header only from the direct-fetch DeepSeek adapter; pi-ai adapter requests sent no session header at all. The installed pi-ai (0.85.1) has no `x-opencode-session` support — its `sessionId` stream option only feeds opt-in `x-session-affinity` headers other providers use — so the session id the loop stamps on every request never reached the wire on that path. Go's own client table lists DeepSeek Harness as problematic for exactly this reason: session information arrives on some model paths but is missing on others.

## Decision

`sessionHeaders()` in `@deepseek-ai/dsh-llm` builds the per-request session routing headers, and both production adapters send them on every chat request carrying a session: the documented `x-opencode-session` plus the native `x-deepseek-harness-session-id` the direct-fetch adapter already sent. Calls without a session send neither. On the pi-ai path the harness value wins over same-named deployment `headers`, because routing must follow the loop-stamped conversation identity, not a static configured string. The native header is retained, not replaced: Go recognizes it, other OpenAI-compatible endpoints ignore unknown headers, and removal would risk consumers the harness cannot see.

## Alternatives considered

**Native header only, extended to all adapters.** This is what Go's client table literally asks for ("send it across all adapters"). It lost because the observed `400` names `x-opencode-session` explicitly, and the documented contract is the safer fix target; sending both headers costs one header and satisfies both readings.

**`x-opencode-session` only, dropping the native header.** The native header already ships in production on the DeepSeek path, so removal is a compatibility risk with no routing benefit. Additive change keeps rollback to a revert.

**Config-gated opt-in per profile.** Session routing identity is loop-owned, not deployment-varying: a flag nobody enables reproduces the reported failure, and there is no legitimate deployment that wants its conversations unroutable.

## Consequences

Session-bearing chat requests on both adapters now carry two extra headers; session-less calls are byte-identical to before. The helper spec pins the mapping and the empty case, and each adapter spec pins presence, absence, and (pi-ai) precedence over deployment headers, which keeps the new module at full coverage. Both adapter READMEs name the headers. A gateway that rejects unknown headers would turn this additive fix into a failure, but no supported OpenAI-compatible endpoint does; the direct-fetch adapter already sent custom `x-deepseek-harness-*` headers in production.
