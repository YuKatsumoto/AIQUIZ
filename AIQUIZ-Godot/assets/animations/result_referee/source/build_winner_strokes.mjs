import fs from 'node:fs/promises';

// Emit Higgsfield AE bridge calls for the editable P1/P2 winner title.
// Coordinates were measured from the existing Noto Sans JP Bold title at
// 1280x720. Each mask exposes one pen stroke of the original text layer.
const destination = process.argv[2];
if (!destination) throw new Error('Pass an output JSON path');

const rect = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
const common = [
  ['P stem', rect(180, 49, 196, 105), 'left'],
  ['P bowl', rect(189, 49, 222, 87), 'top'],
];
const numerals = {
  P1: [
    ['1 cap', rect(226, 49, 255, 70), 'right'],
    ['1 stem', rect(241, 58, 261, 105), 'bottom'],
  ],
  P2: [
    ['2 curve', rect(223, 49, 261, 79), 'right'],
    ['2 diagonal', [[248, 69], [262, 69], [237, 98], [222, 98]], 'bottom'],
    ['2 base', rect(223, 91, 261, 105), 'left'],
  ],
};
const ending = [
  ['W left down', [[294, 49], [311, 49], [326, 105], [310, 105]], 'top'],
  ['W left up', [[309, 105], [325, 105], [341, 49], [324, 49]], 'left'],
  ['W right down', [[321, 49], [340, 49], [351, 105], [335, 105]], 'top'],
  ['W right up', [[338, 105], [355, 105], [360, 49], [344, 49]], 'right'],
  ['I stem', rect(364, 49, 378, 105), 'bottom'],
  ['N left stem', rect(387, 49, 403, 105), 'left'],
  ['N diagonal', [[391, 49], [406, 49], [430, 105], [412, 105]], 'top'],
  ['N right stem', rect(414, 49, 430, 105), 'right'],
];

const transform = ['ADBE Transform Group'];
const opacity = [...transform, 'ADBE Opacity'];
const position = [...transform, 'ADBE Position'];
const op = (operation, args) => ({ operation, args });
const allOps = [];

for (const player of ['P2', 'P1']) {
  const comp = `AIQUIZ_Winner_Strokes_${player}`;
  const pieces = [...common, ...numerals[player], ...ending];
  allOps.push(op('comp.set_props', { comp, props: { motionBlur: true, shutterAngle: 180 } }));

  pieces.forEach(([label, absoluteMask, side], index) => {
    const name = `Stroke ${String(index + 1).padStart(2, '0')} - ${label}`;
    const start = 9.40 + index * (0.90 / (pieces.length - 1));
    const hit = start + 0.17;
    const settle = start + 0.23;
    const overshoot = 9;
    let launch;
    let impact;
    if (side === 'left') {
      launch = [-520, -70];
      impact = [overshoot, 0];
    } else if (side === 'right') {
      launch = [1100, -50];
      impact = [-overshoot, 0];
    } else if (side === 'top') {
      launch = [70, -205];
      impact = [0, overshoot];
    } else {
      launch = [-45, 690];
      impact = [0, -overshoot];
    }
    const toLayer = absoluteMask.map(([x, y]) => [x - 305, y - 103]);

    allOps.push(op('layer.duplicate', { comp, layer: 'Final winner', newName: name }));
    allOps.push(op('keyframe.remove', { comp, layer: name, property: opacity, keyIndex: 2 }));
    allOps.push(op('keyframe.remove', { comp, layer: name, property: opacity, keyIndex: 1 }));
    allOps.push(op('property.set', { comp, layer: name, property: opacity, value: 100 }));
    allOps.push(op('mask.add', { comp, layer: name, name: label }));
    allOps.push(op('mask.set_path', { comp, layer: name, maskIndex: 1, vertices: toLayer }));
    allOps.push(op('layer.set_props', { comp, layer: name,
      props: { inPoint: start, outPoint: 10.68, motionBlur: true, label: 10 } }));
    allOps.push(op('keyframe.set_batch', { comp, layer: name, property: position,
      times: [start, hit, settle],
      values: [
        [305 + launch[0], 103 + launch[1], 0],
        [305 + impact[0], 103 + impact[1], 0],
        [305, 103, 0],
      ] }));
    for (let keyIndex = 1; keyIndex <= 3; keyIndex++) {
      allOps.push(op('keyframe.set_easing', { comp, layer: name, property: position,
        keyIndex, preset: keyIndex === 1 ? 'easeOut' : 'ease' }));
    }
  });

  // The intact type takes over on the final beat and keeps the original
  // victory pulse at 11.4667s. Stroke copies end after the handoff.
  allOps.push(op('keyframe.remove', { comp, layer: 'Final winner', property: opacity, keyIndex: 2 }));
  allOps.push(op('keyframe.remove', { comp, layer: 'Final winner', property: opacity, keyIndex: 1 }));
  allOps.push(op('keyframe.set_batch', { comp, layer: 'Final winner', property: opacity,
    times: [9.333333333, 10.53, 10.666666667], values: [0, 0, 100] }));
  allOps.push(op('keyframe.set_easing', { comp, layer: 'Final winner', property: opacity,
    keyIndex: 3, preset: 'easeIn' }));
  allOps.push(op('layer.set_props', { comp, layer: 'Final winner',
    props: { name: 'Final winner / editable hold', label: 1 } }));
}

const chunkSize = 44;
const requests = [];
for (let index = 0; index < allOps.length; index += chunkSize) {
  requests.push({ name: 'ae_do', arguments: { operation: 'batch.run',
    args: { ops: allOps.slice(index, index + chunkSize), stopOnError: true } } });
}
await fs.writeFile(destination, JSON.stringify(requests, null, 2));
console.log(`Prepared ${allOps.length} AE operations in ${requests.length} batches`);
