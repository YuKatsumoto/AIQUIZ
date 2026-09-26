import fs from 'node:fs/promises';

// Run with --request <file> to prepare native AE property queries, or with a
// saved local MCP response file to export the runtime motion tracks.
const definitions = JSON.parse(await fs.readFile(new URL('./tracks.json', import.meta.url), 'utf8'));
if (process.argv[2] === '--request') {
  const ops = [];
  for (const def of Object.values(definitions)) {
    for (let frame = 0; frame < def.samples; frame++) {
      ops.push({ operation: 'property.get', args: {
        comp: def.comp, layer: def.layer,
        property: ['ADBE Transform Group', def.prop],
        time: def.start + def.duration * frame / (def.samples - 1),
      }});
    }
  }
  const requests = [];
  // Native AE dispatch can outlive one bridge request on larger animations.
  for (let start = 0; start < ops.length; start += 80) {
    requests.push({ name: 'ae_do', arguments: {
      operation: 'batch.run', args: { ops: ops.slice(start, start + 80), stopOnError: true },
    }});
  }
  await fs.writeFile(process.argv[3], JSON.stringify(requests, null, 2));
  console.log(`Prepared ${ops.length} native AE samples`);
} else {
  if (!process.argv[2]) throw Error('Provide --request <file> or an AE response JSON file');
  const responses = JSON.parse(await fs.readFile(process.argv[2], 'utf8'));
  const samples = responses.flatMap(({ result }) => {
    const response = result.structuredContent;
    if (!response?.ok || response.result.failed) throw Error('Native AE sampling failed');
    return response.result.results;
  });
  const data = { source: 'Adobe After Effects 2026 via Higgsfield use After Effects local MCP',
    composition: 'AIQUIZ_Result_Ceremony_v1', fps: 60, tracks: {} };
  let cursor = 0;
  for (const [name, def] of Object.entries(definitions)) {
    const values = [];
    for (let frame = 0; frame < def.samples; frame++) {
      const sample = samples[cursor++];
      if (!sample?.ok) throw Error(`Missing AE sample: ${name}/${frame}`);
      const value = def.component === undefined ? sample.value : sample.value[def.component];
      if (!Number.isFinite(value)) throw Error(`Invalid AE sample: ${name}/${frame}`);
      values.push(Number(((value + (def.offset || 0)) / def.divisor).toFixed(7)));
    }
    data.tracks[name] = { duration: def.duration, values };
  }
  if (cursor !== samples.length) throw Error('AE sample count does not match track definitions');
  await fs.writeFile(new URL('../motion.json', import.meta.url), JSON.stringify(data, null, 2));
  console.log(`Exported ${cursor} samples in ${Object.keys(data.tracks).length} motion tracks`);
}
