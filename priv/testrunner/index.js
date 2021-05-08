import runner from './testRunner.js';
import Colors from './colors.js';

const testFiles = process.argv.slice(2);
console.time('Finished in');
runner
  .start(testFiles)
  .then((results) => {
    const testsFailed = results.failed > 0;

    process.stdout.write('\n\n');
    console.timeEnd('Finished in');
    console.log(
      testsFailed ? Colors.fg.Red : Colors.fg.Green,
      `${results.tests} tests, ${results.success} succeeded, ${results.failed} failed\n`,
      Colors.Reset,
    );

    if (testsFailed) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  })
  .catch((e) => {
    console.log(e);
  });
