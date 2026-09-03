const fs = require('fs');

const dir = '/app/public/vite/assets';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.js'));

for (const f of files) {
  const filePath = `${dir}/${f}`;
  let code = fs.readFileSync(filePath, 'utf8');
  let modified = false;

  if (code.includes('label:c("SIDEBAR.CALLS")') || code.includes('label:t("SIDEBAR.CALLS")')) {
    code = code.replaceAll('label:c("SIDEBAR.CALLS")', 'label:"Calls (Disabled)"');
    code = code.replaceAll('label:t("SIDEBAR.CALLS")', 'label:"Calls (Disabled)"');
    modified = true;
  }
  
  if (code.includes('"CALLS":"Calls"')) {
    code = code.replaceAll('"CALLS":"Calls"', '"CALLS":"Calls (Disabled)"');
    modified = true;
  }

  if (modified) {
    fs.writeFileSync(filePath, code, 'utf8');
    console.log('Updated Calls label in', f);
  }
}
