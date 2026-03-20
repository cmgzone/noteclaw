const esbuild = require('esbuild');

esbuild
  .build({
    entryPoints: ['./src/index.ts'],
    bundle: true,
    platform: 'node',
    format: 'cjs',
    target: ['node20'],
    outfile: './github-install/index.cjs',
    legalComments: 'none',
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
