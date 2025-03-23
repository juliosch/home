import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const __fileName = __dirname + '/../bash/control-wiz.sh';

export function controlWiz(ip, brightness=20, temperature=2200, status="on") {
  return new Promise((resolve, reject) => {
    exec(`${__fileName} --ip ${ip} -${status} -b ${brightness} -t ${temperature}`, (err, stdout) => {
      if (err) {
        reject(err);
      } else {
        resolve(stdout);
      }
    });
  });
}
