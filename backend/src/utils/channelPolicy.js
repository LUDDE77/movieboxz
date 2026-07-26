// Content Sourcing Policy — programmatic enforcement.
// See /CONTENT_SOURCING_POLICY.md. The core, API-verifiable rule is channel age:
// MovieBoxZ does not source from channels younger than one year (a brand-new
// account is the classic signature of a reupload/piracy channel trying to slip
// past YouTube's systems). Subscriber/video counts are recorded as supporting
// signals of an established, legitimate operation.

export const SOURCING_MIN_AGE_DAYS = 365

/**
 * Evaluate a YouTube channel (as returned by youtubeService.getChannelInfo)
 * against the content-sourcing policy.
 * @returns {{ eligible: boolean, ageDays: number|null, ageYears: number|null,
 *             subscriberCount: number|null, videoCount: number|null, reasons: string[] }}
 */
export function evaluateChannelSourcing(channelInfo, { minAgeDays = SOURCING_MIN_AGE_DAYS } = {}) {
    const reasons = []

    let ageDays = null
    if (channelInfo?.publishedAt) {
        const created = new Date(channelInfo.publishedAt).getTime()
        if (!Number.isNaN(created)) {
            ageDays = Math.floor((Date.now() - created) / 86_400_000)
        }
    }

    const ageOk = ageDays != null && ageDays >= minAgeDays
    if (ageDays == null) {
        reasons.push('channel creation date unavailable')
    } else if (!ageOk) {
        reasons.push(`channel is ${ageDays} days old (policy minimum ${minAgeDays})`)
    }

    return {
        eligible: ageOk,
        ageDays,
        ageYears: ageDays != null ? Math.round((ageDays / 365) * 10) / 10 : null,
        subscriberCount: channelInfo?.subscriberCount ?? null,
        videoCount: channelInfo?.videoCount ?? null,
        reasons
    }
}
