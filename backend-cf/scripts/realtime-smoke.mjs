import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import WebSocket from 'ws';

// Match URLSession's native Bearer-header handshake, not browser subprotocol auth.
// Synthetic speech only. Never print credentials, audio, or conversation text.
export async function verifyRealtimeConversation(credentials) {
  const directory = mkdtempSync(join(tmpdir(), 'captro-realtime-'));
  const phrases = [
    'Hello Captro can you help me prepare a post?',
    'I would like to use my last video.',
    'Can you take my video and make it a fifteen second story?',
    'Do not add captions.',
    'Thanks. What should I do next?',
  ];
  try {
    const synthesize = (phrase, index) => {
      const file = join(directory, `${index}.wav`);
      execFileSync('espeak-ng', ['-w', file, '-s', '145', phrase]);
      return execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-i', file,
        '-f', 's16le', '-ac', '1', '-ar', '24000', 'pipe:1'], { maxBuffer: 2_000_000 });
    };
    const clips = phrases.map(synthesize);
    const incompleteThought = synthesize('Can you take my video and', 'pause-start');
    const thoughtCompletion = synthesize('make it a fifteen second story?', 'pause-finish');
    clips[2] = Buffer.concat([incompleteThought, Buffer.alloc(48_000), thoughtCompletion]);
    return await new Promise((resolve, reject) => {
      const socket = new WebSocket(`wss://api.openai.com/v1/realtime?model=${credentials.model}`, {
        headers: { Authorization: `Bearer ${credentials.client_secret}` }, handshakeTimeout: 15_000,
      });
      const seen = new Set();
      const requestedItems = new Set();
      const turns = [];
      let current = null;
      let settled = false;
      let framesSent = 0;
      let activeResponse = null;
      let replyPending = false;
      const pendingItems = [];
      const audioResponses = new Set();
      let cancellations = 0;
      let pausePassed = false;
      let prematurePauseCommit = false;
      let pauseEndFrame = 0;
      const requestReply = () => {
        if (activeResponse || replyPending || !pendingItems.length) return;
        pendingItems.shift();
        replyPending = true;
        socket.send(JSON.stringify({ type: 'response.create' }));
      };
      const finish = error => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        socket.close();
        if (error) reject(error);
        else resolve({ transport: 'native_bearer_websocket', vad: 'semantic_vad', eagerness: 'medium',
          create_response: false, automatic_client_response: true, frames_sent: framesSent,
          turns, cancellations, natural_pause_preserved: pausePassed, history_rehydration: true, events: [...seen] });
      };
      const timeout = setTimeout(() => finish(new Error(`Realtime timed out: completed_turns=${turns.length}, events=${[...seen].join(',')}`)), 180_000);
      const delay = ms => new Promise(r => setTimeout(r, ms));
      const sendPcm = bytes => {
        socket.send(JSON.stringify({ type: 'input_audio_buffer.append', audio: bytes.toString('base64') }));
        framesSent += bytes.length / 2;
      };
      const run = async () => {
        for (const clip of clips) {
          if (settled) return;
          current = { speech_started: false, completed_turn: false, response_created: false,
            audio_received: false, transcript: false, response_completed: false };
          if (turns.length === 2) pauseEndFrame = framesSent + 2400 + incompleteThought.length / 2 + 24000;
          sendPcm(Buffer.alloc(4_800));
          for (let offset = 0; offset < clip.length && !settled; offset += 4_800) {
            sendPcm(clip.subarray(offset, offset + 4_800));
            await delay(100);
          }
          current.input_finished = true;
          // Only OpenAI VAD commits the turn. Silence is streamed audio, not a
          // homegrown turn timer; no input_audio_buffer.commit is sent.
          while (!settled && !current.response_completed) {
            sendPcm(Buffer.alloc(4_800));
            await delay(100);
          }
          if (settled) return;
          assert.ok(current.speech_started && current.completed_turn && current.response_created
            && current.audio_received, 'Incomplete automatic conversational turn');
          if (turns.length === 2) assert.ok(pausePassed, 'Incomplete thought was committed before its continuation');
          turns.push(current);
        }
        finish();
      };
      let configured = false;
      socket.on('message', data => {
        try {
          const message = JSON.parse(data.toString());
          seen.add(message.type);
          if (['input_audio_buffer.speech_started', 'input_audio_buffer.speech_stopped', 'input_audio_buffer.committed', 'response.created', 'response.done'].includes(message.type)) {
            console.log(JSON.stringify({ stage: 'realtime_event', type: message.type, turn: turns.length + 1,
              status: message.response?.status || null, frames_sent: framesSent }));
          }
          if (message.type === 'session.created') {
            socket.send(JSON.stringify({ type: 'session.update', session: { type: 'realtime', audio: {
              input: { format: { type: 'audio/pcm', rate: 24000 }, turn_detection: {
                type: 'semantic_vad', eagerness: 'medium', create_response: false, interrupt_response: true,
              } }, output: { format: { type: 'audio/pcm', rate: 24000 } },
            } } }));
          } else if (message.type === 'session.updated' && !configured) {
            configured = true;
            const vad = message.session?.audio?.input?.turn_detection;
            assert.equal(vad?.type, 'semantic_vad');
            assert.equal(vad?.create_response, false);
            assert.equal(vad?.interrupt_response, true);
            // Match native reconnection history restoration. These are bounded
            // synthetic messages, not anyone's private conversation.
            socket.send(JSON.stringify({ type: 'conversation.item.create', item: {
              type: 'message', role: 'user', content: [{ type: 'input_text', text: 'We are preparing a Captro post.' }],
            } }));
            socket.send(JSON.stringify({ type: 'conversation.item.create', item: {
              type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Sure. What would you like to prepare?' }],
            } }));
            void run().catch(finish);
          } else if (message.type === 'input_audio_buffer.speech_started' && current) {
            current.speech_started = true;
          } else if (message.type === 'input_audio_buffer.committed' && current) {
            if (turns.length === 2) {
              if (framesSent < pauseEndFrame) prematurePauseCommit = true;
              pausePassed = !prematurePauseCommit && framesSent >= pauseEndFrame;
            }
            current.completed_turn = true;
            if (!requestedItems.has(message.item_id)) {
              requestedItems.add(message.item_id);
              pendingItems.push(message.item_id);
              requestReply();
            }
          } else if (message.type === 'response.created' && current) {
            current.response_created = true;
            activeResponse = message.response?.id;
            replyPending = false;
          } else if (message.type === 'response.output_audio.delta' && current) {
            current.audio_received = true;
            audioResponses.add(message.response_id);
          } else if (message.type === 'conversation.item.input_audio_transcription.completed' && current) {
            current.transcript = !!message.transcript;
          } else if (message.type === 'response.done' && current) {
            const status = message.response?.status;
            assert.ok(['completed', 'cancelled'].includes(status), `Response failed: ${message.response?.status_details?.error?.code || status}`);
            if (status === 'cancelled') cancellations += 1;
            if (activeResponse === message.response?.id) activeResponse = null;
            if (status === 'completed' && current.input_finished && audioResponses.has(message.response.id) && !pendingItems.length) {
              current.response_completed = true;
            }
            requestReply();
          } else if (message.type === 'error') {
            finish(new Error(`Realtime API ${message.error?.type || 'error'}: ${message.error?.code || 'unknown'}`));
          }
        } catch (error) { finish(error); }
      });
      socket.on('unexpected-response', (_request, response) => {
        response.resume();
        finish(new Error(`Realtime upgrade HTTP ${response.statusCode}; request_id=${response.headers['x-request-id'] || 'unavailable'}`));
      });
      socket.on('error', error => finish(new Error(`Realtime transport error: ${error.code || error.name}`)));
      socket.on('close', code => { if (!settled) finish(new Error(`Realtime closed ${code}; completed_turns=${turns.length}`)); });
    });
  } finally { rmSync(directory, { recursive: true, force: true }); }
}
