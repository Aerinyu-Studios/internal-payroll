// Optional development-environment compatibility fix. Vite treats a denied
// Windows drive-mapping subprocess as fatal although that lookup is optional.
import fs from 'node:fs';
if(process.platform==='win32'){
 const p=new URL('../node_modules/vite/dist/node/chunks/node.js',import.meta.url);let s=fs.readFileSync(p,'utf8');
 if(!s.includes('Optional drive mapping unavailable')){
  s=s.replace('exec("net use", (error, stdout) => {','try { exec("net use", (error, stdout) => {').replace('else safeRealpathSync = windowsMappedRealpathSync;\n\t});','else safeRealpathSync = windowsMappedRealpathSync;\n\t}); } catch { /* Optional drive mapping unavailable in restricted Windows environments. */ }');
  fs.writeFileSync(p,s);
 }
}
