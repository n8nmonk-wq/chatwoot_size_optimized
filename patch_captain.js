const fs = require('fs');
const glob = require('path');

const dir = '/app/public/vite/assets';
const files = fs.readdirSync(dir).filter(f => f.startsWith('dashboard-') && f.endsWith('.js'));

for (const f of files) {
  const filePath = `${dir}/${f}`;
  let code = fs.readFileSync(filePath, 'utf8');
  
  // Look for the Captain object in sidebar navigation
  const targetPattern = /\{name:"Captain",icon:"i-woot-captain"[\s\S]*?navigationPath:"captain_assistants_settings_index"\}\)\}\]\},/g;
  
  if (targetPattern.test(code)) {
    code = code.replace(targetPattern, '');
    fs.writeFileSync(filePath, code, 'utf8');
    console.log(`Successfully patched and removed Captain from ${f}`);
  } else {
    // Alternate match if slightly different
    console.log(`Testing broader pattern on ${f}...`);
    const startStr = '{name:"Captain",icon:"i-woot-captain"';
    const start = code.indexOf(startStr);
    if (start !== -1) {
      const endMarker = 'navigationPath:"captain_assistants_settings_index"})}]';
      const end = code.indexOf(endMarker, start);
      if (end !== -1) {
        let fullEnd = end + endMarker.length;
        if (code[fullEnd] === '}') fullEnd++;
        if (code[fullEnd] === ',') fullEnd++;
        code = code.substring(0, start) + code.substring(fullEnd);
        fs.writeFileSync(filePath, code, 'utf8');
        console.log(`Successfully spliced Captain out of ${f}`);
      }
    }
  }
}
