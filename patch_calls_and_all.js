const fs = require('fs');

const dir = '/app/public/vite/assets';
const files = fs.readdirSync(dir).filter(f => f.startsWith('dashboard-') && f.endsWith('.js'));

for (const f of files) {
  const filePath = `${dir}/${f}`;
  let code = fs.readFileSync(filePath, 'utf8');
  let modified = false;

  // 1. Update Calls empty state / setup texts
  const oldCallsTitle = "Make and receive calls in one place";
  const newCallsTitle = "Calls & Voice Channel (Disabled for Resource Optimization)";
  if (code.includes(oldCallsTitle)) {
    code = code.replaceAll(oldCallsTitle, newCallsTitle);
    modified = true;
    console.log("Updated Calls title in", f);
  }

  const oldCallsSubtitle = "Set up a voice channel to start handling calls with your team. Every call, along with its recording, will appear here.";
  const newCallsSubtitle = "This feature has been removed to save space, RAM, and CPU resources on your VPS. Your server is streamlined and optimized for WhatsApp Marketing and Meta Cloud API messaging.";
  if (code.includes(oldCallsSubtitle)) {
    code = code.replaceAll(oldCallsSubtitle, newCallsSubtitle);
    modified = true;
    console.log("Updated Calls subtitle in", f);
  }

  const oldCallsAction = "Set up voice channel";
  const newCallsAction = "Optimized for WhatsApp Marketing";
  if (code.includes(oldCallsAction)) {
    code = code.replaceAll(oldCallsAction, newCallsAction);
    modified = true;
    console.log("Updated Calls button action in", f);
  }

  // 2. Update Calls sidebar label to "Calls (Disabled)"
  if (code.includes('label:c("SIDEBAR.CALLS")')) {
    code = code.replaceAll('label:c("SIDEBAR.CALLS")', 'label:"Calls (Disabled)"');
    modified = true;
    console.log("Updated Calls sidebar label in", f);
  }

  // 3. Ensure Captain appears cleanly in sidebar as Captain (Disabled)
  if (code.includes('name:"Calls"') && !code.includes('label:"Captain (Disabled)"')) {
    const captainObj = '{name:"Captain",icon:"i-woot-captain",label:"Captain (Disabled)",to:a("portals_index"),activeOn:["captain_assistants_overview_index"]},';
    code = code.replace('name:"Calls"', 'name:"Captain",icon:"i-woot-captain",label:"Captain (Disabled)",to:a("portals_index"),activeOn:["captain_assistants_overview_index"]},{name:"Calls"');
    modified = true;
    console.log("Inserted Captain (Disabled) next to Calls in", f);
  }

  if (modified) {
    fs.writeFileSync(filePath, code, 'utf8');
    console.log("Successfully wrote all updates to", f);
  }
}
