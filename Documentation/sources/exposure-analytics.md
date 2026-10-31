# Exposure analytics

When your app evaluates a feature that is part of an experiment, the Flags extension records an exposure: a record that the user was shown a variant. The extension sends exposures to Adobe Experience Platform through the Edge Network extension, so you can measure your experiments.

- [What is sent](#what-is-sent)
- [When exposures are recorded](#when-exposures-are-recorded)
- [Batching](#batching)
- [Risk of losing exposures](#risk-of-losing-exposures)
- [Correlation ID formats](#correlation-id-formats)

## What is sent

Each exposure is an Experience Event with the event type `decisioning.propositionDisplay`. The extension sends it through the Edge Network extension to the datastream configured in your mobile property. The Edge Network extension adds the user's identities from Identity for Edge Network, and it applies the user's collect consent in the same way as for other Experience Events.

Key fields in the XDM payload:

| Field | Value |
| --- | --- |
| `eventType` | `decisioning.propositionDisplay` |
| `timestamp` | The time of the most recent evaluation in the batch |
| `_experience.decisioning.propositionEventType.display` | The number of evaluations combined into this event |
| `_experience.decisioning.propositions[].scopeDetails.decisionProvider` | `FLAGS` |
| `_experience.decisioning.propositions[].scopeDetails.correlationID` | See [Correlation ID formats](#correlation-id-formats) |
| `_experience.decisioning.propositions[].scopeDetails.activity.id` | `FG-<featureGroupId>` for a feature in a feature group, or `F-<featureId>` for a feature without a feature group |
| `_experience.decisioning.propositions[].scopeDetails.activity.name` | The feature group key, or the feature key for a feature without a feature group |
| `_experience.decisioning.propositions[].scopeDetails.experience.id` | `Variant-<variantId>` |
| `_experience.decisioning.propositions[].scopeDetails.characteristics.entityType` | `featureGroup` or `feature` |
| `_experience.decisioning.propositions[].items[]` | For a feature in a feature group, the feature ID (`id`) and the feature key (`name`) |

## When exposures are recorded

Both `isFeatureEnabled` and `getFeature` record exposures.

| Situation | Exposure recorded |
| --- | --- |
| The feature is part of an experiment and applies to the user | Yes |
| The user is in the control group of a feature | Yes |
| The user is in the control group of a feature group | No |
| The feature isn't part of an experiment | No |
| No feature has this key | No |
| The user doesn't match the targeting rules | No |
| The evaluation fails with an error before it completes | No |

For a user in the control group of a feature, `getFeature` reports an error to your app, but the exposure is still recorded.

## Batching

The extension doesn't send an event for every evaluation. Evaluations of the same feature and variant are combined into one event, and the `display` field holds the number of evaluations.

Pending exposures are sent when any of these happens:

- 20 different feature and variant combinations are pending.
- 150 seconds have passed since the batch started.
- The app moves to the background. This requires the `MobileCore.lifecyclePause` call, which `MobileCore.initialize` makes for you. See [Initialize the SDK](getting-started.md#initialize-the-sdk).

While the app is in the background, the 150-second timer is stopped. It starts again when the app returns to the foreground.

Evaluation calls return their result right away. They don't wait for exposures to be sent.

## Risk of losing exposures

Until they are sent, pending exposures are kept in memory only. If the app is terminated or crashes before a batch is sent, those exposures are lost.

To reduce this risk, make sure the app reports background transitions. Use `MobileCore.initialize`, or call `MobileCore.lifecyclePause` when the app enters the background.

After the extension passes exposures to the Edge Network extension, the Edge Network extension stores and sends them in the same way as other Experience Events.

## Correlation ID formats

| Feature | Correlation ID |
| --- | --- |
| Feature in a feature group | `FG-<featureGroupId>-<variantId>` |
| Feature without a feature group | `F-<featureId>-<variantId>` |

The IDs match the `featureGroupId`, `featureId`, and `variantId` values in the `analyticsParam` property of a [`FeatureEvaluationResult`](api-usage.md#featureevaluationresult).
