const esbuild = require('esbuild');
const { readFile, writeFile } = require('node:fs/promises');

const outputFile = './github-install/index.cjs';

esbuild
  .build({
    entryPoints: ['./src/index.ts'],
    bundle: true,
    platform: 'node',
    format: 'cjs',
    target: ['node20'],
    outfile: outputFile,
    legalComments: 'none',
    banner: {
      js: 'var __noteclawImportMetaUrl = require("node:url").pathToFileURL(__filename).href;',
    },
    define: {
      'import.meta.url': '__noteclawImportMetaUrl',
    },
  })
  .then(async () => {
    const bundled = await readFile(outputFile, 'utf8');
    await writeFile(outputFile, bundled.replace(/[ \t]+$/gm, ''), 'utf8');
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
