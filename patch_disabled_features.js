const fs = require('fs');

const dir = '/app/public/vite/assets';
const files = fs.readdirSync(dir).filter(f => f.startsWith('dashboard-') && f.endsWith('.js'));

for (const f of files) {
  const filePath = `${dir}/${f}`;
  let code = fs.readFileSync(filePath, 'utf8');
  let modified = false;

  // 1. Update Help Center self-hosted text in compiled bundle
  const oldHelpCenterText = "Create user-friendly self-service portals. Help your users to access the articles and get support 24/7. Please contact your administrator to enable this feature.";
  const newHelpCenterText = "This feature has been removed to save space, RAM, and CPU resources on your VPS. Your server is streamlined and optimized for WhatsApp Marketing and Meta Cloud API messaging.";
  
  if (code.includes(oldHelpCenterText)) {
    code = code.replaceAll(oldHelpCenterText, newHelpCenterText);
    modified = true;
    console.log("Updated Help Center disabled text in", f);
  }

  // 2. Add Captain back into sidebar navigation as a disabled feature entry pointing to an informative view
  if (!code.includes('{name:"Captain",icon:"i-woot-captain"')) {
    const contactsMarker = '{name:"Contacts",';
    if (code.includes(contactsMarker)) {
      const captainEntry = '{name:"Captain",icon:"i-woot-captain",label:"Captain (Disabled)",to:a("portals_index"),activeOn:["captain_assistants_overview_index"]},';
      code = code.replace(contactsMarker, captainEntry + contactsMarker);
      modified = true;
      console.log("Re-added Captain as (Disabled) entry pointing to Resource Saver in", f);
    }
  }

  // 3. Update Help Center sidebar label to "Help Center (Disabled)"
  if (code.includes('label:c("SIDEBAR.HELP_CENTER.TITLE")')) {
    code = code.replace('label:c("SIDEBAR.HELP_CENTER.TITLE")', 'label:"Help Center (Disabled)"');
    modified = true;
    console.log("Updated Help Center sidebar label to 'Help Center (Disabled)' in", f);
  }

  if (modified) {
    fs.writeFileSync(filePath, code, 'utf8');
    console.log("Successfully wrote updates to", f);
  } else {
    console.log("No matching targets found or already modified in", f);
  }
}
