// Rulează: node --test terraform/modules/edge/functions/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('./spa-rewrite.js', import.meta.url), 'utf8');
const handler = new Function(`${src}\nreturn handler;`)();
const run = (uri, host = 'aradex.example') => handler({ request: { uri, headers: { host: { value: host } } } });

test('deep SPA link goes to index.html', () => assert.equal(run('/m/events/42').uri, '/index.html'));
test('/w goes to index.html', () => assert.equal(run('/w').uri, '/index.html'));
test('root goes to index.html', () => assert.equal(run('/').uri, '/index.html'));
test('hashed asset untouched', () => assert.equal(run('/assets/index-abc.js').uri, '/assets/index-abc.js'));
test('service worker untouched', () => assert.equal(run('/sw.js').uri, '/sw.js'));
test('www redirects to apex with same path', () => {
  const res = run('/m', 'www.aradex.example');
  assert.equal(res.statusCode, 301);
  assert.equal(res.headers.location.value, 'https://aradex.example/m');
});
