const fs = require('fs');

exports('writeFile', (path, content) => {
  try {
    fs.writeFileSync(path, content, 'utf8');
    return { ok: true };
  } catch (e) {
    return { ok: false, err: `${e.code || 'ERROR'}: ${e.message}` };
  }
});
