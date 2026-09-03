const fs = require('fs');

const file = '/app/public/vite/assets/dashboard-Brz794dT.js';
let content = fs.readFileSync(file, 'utf8');

// Find the sidebar items array
const startMarker = 'name:"Conversations"';
const start = content.indexOf(startMarker);
const end = content.indexOf('name:"Settings"', start);

console.log("=== CURRENT SIDEBAR SECTION ===");
console.log(content.substring(start, end + 100));
