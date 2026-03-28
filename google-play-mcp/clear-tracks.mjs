#!/usr/bin/env node

import * as dotenv from 'dotenv';
import { google } from 'googleapis';

dotenv.config();

const packageName = process.env.GOOGLE_PLAY_PACKAGE_NAME || 'com.gavra013.gavra_android';
const keyJson = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_KEY;
const tracksToClear = ['alpha', 'internal'];

async function run() {
    if (!keyJson) {
        throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_KEY not set');
    }

    const credentials = JSON.parse(keyJson);
    const auth = new google.auth.GoogleAuth({
        credentials,
        scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });

    const androidpublisher = google.androidpublisher({ version: 'v3', auth });

    for (const track of tracksToClear) {
        const editResp = await androidpublisher.edits.insert({ packageName, requestBody: {} });
        const editId = editResp.data.id;
        if (!editId) {
            throw new Error(`No edit id for track ${track}`);
        }

        let previousReleases = [];
        try {
            const current = await androidpublisher.edits.tracks.get({ packageName, editId, track });
            previousReleases = current.data.releases || [];
        } catch (error) {
            await androidpublisher.edits.delete({ packageName, editId });
            console.log(`⚠️ Track '${track}' nije pronađen, preskačem.`);
            continue;
        }

        await androidpublisher.edits.tracks.update({
            packageName,
            editId,
            track,
            requestBody: {
                track,
                releases: [],
            },
        });

        await androidpublisher.edits.commit({ packageName, editId });

        console.log(`✅ Očišćen track '${track}'.`);
        if (previousReleases.length > 0) {
            for (const rel of previousReleases) {
                const versions = rel.versionCodes?.join(', ') || 'N/A';
                console.log(`   - prethodno: v${versions} (${rel.status || 'unknown'})`);
            }
        } else {
            console.log('   - prethodno: nema release-ova');
        }
    }
}

run().catch((error) => {
    console.error('❌ Greška:', error.message);
    process.exit(1);
});
