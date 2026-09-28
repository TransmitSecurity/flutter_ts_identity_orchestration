package com.flutter_ts_identity_orchestration

import com.transmit.idosdk.TSIdoClientResponseOption
import com.transmit.idosdk.modularidv.TSIDVAcquisitionContext
import com.transmit.idosdk.modularidv.TSIDVStepHandler
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Which modular IDV acquisition step a hook belongs to. */
internal enum class ModularIDVAcquisition(val wireValue: String) {
  Document("document"),
  Selfie("selfie")
}

/** Which side of the acquisition a hook fires on. */
internal enum class ModularIDVHookPoint(val wireValue: String) {
  OnBefore("onBefore"),
  OnAfter("onAfter")
}

/** How Dart wants a suspended step to continue. */
internal sealed interface ModularIDVResume {
  /** Run the SDK's default flow: start capture (onBefore) or submit the result (onAfter). */
  object Proceed : ModularIDVResume

  /**
   * Bypass the default flow and submit [responseId] instead, branching the journey.
   *
   * [responseId] is the SDK's response-option *type* string, already converted from the raw Dart
   * id by the caller — this bridge deliberately knows nothing about that mapping.
   */
  data class Submit(val responseId: String, val data: Map<String, Any>?) : ModularIDVResume
}

/** Outcome of a resume attempt, so the caller can shape a channel reply without catching. */
internal sealed interface ModularIDVResumeResult {
  object Resumed : ModularIDVResumeResult

  /** No pending hook for the given id: never issued, already consumed, or cleared by a new journey. */
  object UnknownHookId : ModularIDVResumeResult

  /** The SDK rejected the resume. The hook is consumed regardless — retrying it cannot succeed. */
  data class Failed(val cause: Throwable) : ModularIDVResumeResult
}

/**
 * Bridges the native SDK's **synchronous** modular IDV hooks to Dart's **asynchronous** platform
 * channel.
 *
 * This is only possible because of a specific property of the SDK contract: `onBefore`/`onAfter`
 * return `Unit`, and `ModularIDVController` does nothing at all once a hook returns. The step
 * resumes solely through `TSIdoStepContext.proceed()` or `.submit()`. So a hook is
 * fire-and-forget — the bridge can store the context, emit an event, return immediately, and
 * resume the journey much later when Dart calls back. A hook that *returned* a decision could not
 * be bridged this way.
 *
 * The consequence, which is inherent and not a defect: while a hook is pending the journey is
 * **stalled**. Nothing times it out. If Dart never resumes, the step never completes — exactly the
 * semantics a native app gets from these hooks.
 *
 * ### Hooks are opt-in, and must stay that way
 *
 * A nil hook means "proceed automatically", which is the behaviour every existing integration
 * relies on. Installing hooks unconditionally would stall every acquisition step in every app that
 * does not listen — a silent hang, not an error. So [setEnabled] defaults to off and
 * [makeStepHandler] installs only the hooks that have been explicitly enabled from Dart.
 *
 * ### Identity across the channel
 *
 * A `TSIDVAcquisitionContext` cannot cross a platform channel, and there is nothing in the step
 * data that reliably identifies one: `acquisitionId` is nullable, is reused by the before and
 * after hook of the same step, and repeats across the document and selfie steps of one journey. So
 * each hook invocation is assigned a fresh opaque `hookId` and the context is held here. Ids are
 * **single-shot** — consumed on first resume — so a double reply from Dart cannot submit twice.
 */
internal class ModularIDVHookBridge(private val emit: (Map<String, Any?>) -> Unit) {

  /**
   * Pending contexts by hook id.
   *
   * Concurrent because hooks are invoked from the SDK's dispatch path while resumes arrive on the
   * platform-channel thread. Entries are removed on resume or by [reset]; a stalled journey leaves
   * at most one entry per in-flight step, cleared at the next journey start.
   */
  private val pending = ConcurrentHashMap<String, TSIDVAcquisitionContext>()

  @Volatile
  private var onBeforeEnabled = false

  @Volatile
  private var onAfterEnabled = false

  /**
   * Enables or disables each hook.
   *
   * Takes effect from the next acquisition step, not the current one: handlers are produced per
   * step by [makeStepHandler], but a step already suspended in a hook keeps the behaviour it
   * started with. Disabling while a hook is pending does not resume it — [reset] or an explicit
   * resume is still required, otherwise that journey stays stalled.
   */
  fun setEnabled(onBefore: Boolean, onAfter: Boolean) {
    onBeforeEnabled = onBefore
    onAfterEnabled = onAfter
  }

  /** True when at least one hook is enabled, so callers can report the live configuration back. */
  fun isEnabled(): Boolean = onBeforeEnabled || onAfterEnabled

  /**
   * Drops every pending hook.
   *
   * Called at journey start. Contexts from a previous journey are already unusable — their
   * `proceed`/`submit` closures target a step the SDK has moved past — so retaining them would
   * only let Dart resume a dead step and leak the closures for the plugin's lifetime.
   */
  fun reset() {
    pending.clear()
  }

  /**
   * Builds the handler for one acquisition step, installing only the enabled hooks.
   *
   * A fresh [TSIDVStepHandler] per call is deliberate: the SDK asks for a handler per step, and
   * the closures capture [acquisition] so the emitted event can say which step is suspended.
   */
  fun makeStepHandler(acquisition: ModularIDVAcquisition): TSIDVStepHandler {
    val handler = TSIDVStepHandler()

    if (onBeforeEnabled) {
      handler.onBefore = { context -> suspendStep(acquisition, ModularIDVHookPoint.OnBefore, context) }
    }

    if (onAfterEnabled) {
      handler.onAfter = { context -> suspendStep(acquisition, ModularIDVHookPoint.OnAfter, context) }
    }

    return handler
  }

  /**
   * Resumes the step held under [hookId], consuming the id.
   *
   * The id is consumed before the SDK call, not after: `proceed`/`submit` can throw, and a hook
   * that failed to resume cannot be resumed again — the SDK has already delivered the failure
   * through the journey callback. Leaving the id live would invite a retry that silently does
   * nothing.
   */
  fun resume(hookId: String, action: ModularIDVResume): ModularIDVResumeResult {
    val context = pending.remove(hookId) ?: return ModularIDVResumeResult.UnknownHookId

    return try {
      when (action) {
        is ModularIDVResume.Proceed -> context.proceed()
        is ModularIDVResume.Submit -> context.submit(action.responseId, action.data)
      }
      ModularIDVResumeResult.Resumed
    } catch (e: Exception) {
      ModularIDVResumeResult.Failed(e)
    }
  }

  /** Registers [context] under a fresh id and tells Dart the step is waiting. */
  private fun suspendStep(
    acquisition: ModularIDVAcquisition,
    hookPoint: ModularIDVHookPoint,
    context: TSIDVAcquisitionContext
  ) {
    val hookId = UUID.randomUUID().toString()
    pending[hookId] = context
    emit(hookEvent(hookId, acquisition, hookPoint, context))
  }

  /**
   * Shapes the event Dart receives.
   *
   * Two fields of `TSAcquisitionStepData` are withheld on purpose:
   *
   * - **`startToken`** is a live IDV session credential. Dart cannot act on it — only the native
   *   SDK can start acquisition — so putting it on the channel would widen a secret's blast radius
   *   for no capability. iOS withholds it identically.
   * - **`state` and `baseEndpoint`** are hardcoded to null by the SDK's own step decoding at this
   *   version, on both platforms. Emitting always-null keys would imply a contract the SDK does
   *   not have yet.
   */
  private fun hookEvent(
    hookId: String,
    acquisition: ModularIDVAcquisition,
    hookPoint: ModularIDVHookPoint,
    context: TSIDVAcquisitionContext
  ): Map<String, Any?> = mapOf(
    "type" to MODULAR_IDV_HOOK_EVENT_TYPE,
    "hookId" to hookId,
    "hook" to hookPoint.wireValue,
    "acquisitionType" to acquisition.wireValue,
    "acquisitionId" to context.data.acquisitionId,
    "responseOptions" to (context.data.responseOptions?.map(::responseOption) ?: emptyList())
  )

  /**
   * Flattens one response option for the channel.
   *
   * `schema` is omitted: it is the only non-primitive field, and a hook decides *which* branch to
   * take rather than validating input against a schema. The full option, schema included, already
   * reaches Dart on the journey response for this step.
   */
  private fun responseOption(option: TSIdoClientResponseOption): Map<String, Any?> = mapOf(
    "id" to option.id,
    "label" to option.label,
    "type" to option.type.toString()
  )

  internal companion object {
    /** Discriminator on the shared event channel, matched by the Dart side and by iOS. */
    const val MODULAR_IDV_HOOK_EVENT_TYPE = "modularIdvHook"
  }
}
