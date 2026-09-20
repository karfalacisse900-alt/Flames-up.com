const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname,'..');
const {renderStamp} = require('../dist/render-stamp');
const {EXAMPLES} = require('../dist/examples');
for (const density of ['full','compact']) {
  const suffix = density==='compact' ? '-compact' : '';
  for (const example of EXAMPLES) {
    fs.writeFileSync(path.join(root,`assets/svg${suffix}`,`${example.variant}.svg`),renderStamp(example,{density}));
    fs.writeFileSync(path.join(root,`assets/frames${suffix}`,`${example.variant}.svg`),renderStamp(example,{density,frameOnly:true}));
  }
}
fs.writeFileSync(path.join(root,'examples.json'),JSON.stringify(EXAMPLES,null,2));
console.log('Exported 30 editable SVGs + 30 blank vector frames.');
