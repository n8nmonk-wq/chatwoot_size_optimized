const fs = require('fs');

const dir = '/app/public/vite/assets';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.js'));

for (const f of files) {
  const filePath = `${dir}/${f}`;
  let code = fs.readFileSync(filePath, 'utf8');
  
  if (code.includes('Make and receive calls')) {
    console.log('Found in', f);
    code = code.replaceAll('Make and receive calls in one place', 'Calls & Voice Channel (Disabled for Resource Optimization)');
    code = code.replaceAll('Set up a voice channel to start handling calls with your team. Every call, along with its recording, will appear here.', 'This feature has been removed to save space, RAM, and CPU resources on your VPS. Your server is streamlined and optimized for WhatsApp Marketing and Meta Cloud API messaging.');
    code = code.replaceAll('Set up voice channel', 'Optimized for Low-RAM VPS');
    fs.writeFileSync(filePath, code, 'utf8');
    console.log('Replaced in', f);
  }
}
