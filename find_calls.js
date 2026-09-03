const fs = require('fs');

const file = '/app/public/vite/assets/dashboard-Brz794dT.js';
let content = fs.readFileSync(file, 'utf8');

const callsIdx = content.indexOf('name:"Calls"');
console.log("Found Calls at index:", callsIdx);
if (callsIdx !== -1) {
  console.log(content.substring(callsIdx - 150, callsIdx + 200));
}
