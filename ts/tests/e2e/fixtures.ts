// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { type APIRequestContext, test as base } from "@playwright/test";

export { expect } from "@playwright/test";

/**
 * The FAR seed (F016) loaded into the throwaway collection, exposed to specs.
 * `sealedTbsNoteIds` lets B4 deep-link the TBS surface (?note=<id>).
 */
export interface FarSeed {
    confusionSets: number;
    sealedItems: number;
    sealedJeTbs: number;
    sealedNumericTbs: number;
    studyRecallCards: number;
    roteCards: number;
    sealedTbsNoteIds: bigint[];
}

/**
 * Minimal protobuf reader for the LoadFarSeedResponse message. We avoid pulling
 * the generated proto module into the Playwright (Node) context — which has no
 * `@generated` alias — by decoding the handful of fields we need directly.
 *
 * Wire layout (proto3): fields 1..6 are uint32 (wire type 0, varint); field 7
 * is `repeated int64` which protoc encodes packed (wire type 2, length-
 * delimited) by default in proto3.
 */
function decodeLoadFarSeedResponse(bytes: Uint8Array): FarSeed {
    const out: FarSeed = {
        confusionSets: 0,
        sealedItems: 0,
        sealedJeTbs: 0,
        sealedNumericTbs: 0,
        studyRecallCards: 0,
        roteCards: 0,
        sealedTbsNoteIds: [],
    };
    let i = 0;
    const readVarint = (): bigint => {
        let shift = 0n;
        let result = 0n;
        while (i < bytes.length) {
            const b = bytes[i++];
            result |= BigInt(b & 0x7f) << shift;
            if ((b & 0x80) === 0) {
                break;
            }
            shift += 7n;
        }
        return result;
    };
    while (i < bytes.length) {
        const key = Number(readVarint());
        const fieldNo = key >> 3;
        const wireType = key & 0x7;
        if (wireType === 0) {
            const v = Number(readVarint());
            switch (fieldNo) {
                case 1:
                    out.confusionSets = v;
                    break;
                case 2:
                    out.sealedItems = v;
                    break;
                case 3:
                    out.sealedJeTbs = v;
                    break;
                case 4:
                    out.sealedNumericTbs = v;
                    break;
                case 5:
                    out.studyRecallCards = v;
                    break;
                case 6:
                    out.roteCards = v;
                    break;
                default:
                    break;
            }
        } else if (wireType === 2) {
            const len = Number(readVarint());
            const end = i + len;
            if (fieldNo === 7) {
                while (i < end) {
                    out.sealedTbsNoteIds.push(readVarint());
                }
            } else {
                i = end;
            }
        } else {
            // Unexpected wire type; bail to avoid an infinite loop.
            break;
        }
    }
    return out;
}

function encodeLoadFarSeedRequest(withHistory: boolean): Buffer {
    return withHistory ? Buffer.from([0x10, 0x01]) : Buffer.alloc(0);
}

async function loadFarSeed(request: APIRequestContext, withHistory: boolean): Promise<FarSeed> {
    const res = await request.post("/_anki/loadFarSeed", {
        headers: { "Content-Type": "application/binary" },
        data: encodeLoadFarSeedRequest(withHistory),
    });
    if (!res.ok()) {
        throw new Error(`loadFarSeed failed: ${res.status()} ${await res.text()}`);
    }
    const bytes = new Uint8Array(await res.body());
    return decodeLoadFarSeedResponse(bytes);
}

export const test = base.extend<{ seed: FarSeed; seedWithHistory: FarSeed }>({
    seed: async ({ request }, use) => {
        await use(await loadFarSeed(request, false));
    },
    seedWithHistory: async ({ request }, use) => {
        await use(await loadFarSeed(request, true));
    },
});
