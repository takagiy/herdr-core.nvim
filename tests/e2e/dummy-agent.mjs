import { createInterface } from 'node:readline';

const input = createInterface({ input: process.stdin, terminal: false });
const status = (state) => process.stdout.write(`\x1b]7501;state=${state}:app=e2e-agent\x1b\\`);
process.stdout.write(`ready:${process.pid}\n`);
input.on('line', (line) => {
  const [command, ...parts] = line.trim().split(' ');
  const value = parts.join(' ');
  if (command === 'echo') process.stdout.write(`reply:${value}\n`);
  else if (command === 'status' && ['working', 'blocked', 'done', 'idle'].includes(value)) {
    status(value);
    process.stdout.write(`reported:${value}\n`);
  } else if (command === 'exit') input.close();
  else process.stdout.write(`unknown:${command}\n`);
});
