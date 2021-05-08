import rollup from 'rollup'
import babel from 'rollup-plugin-babel'
import nodeResolve from 'rollup-plugin-node-resolve'
import commonjs from 'rollup-plugin-commonjs'
import minify from 'rollup-plugin-babel-minify'

const plugins = [
  nodeResolve({
    mainFields: ['jsnext', 'main'],
  }),
  commonjs(),
  babel({
    babelrc: false,
  }),
  minify({
    keepFnName: true,
    keepClassName: true,
  }),
]

rollup
  .rollup({
    input: 'src/javascript/elixir.js',
    output: {
      file: 'priv/build/es/ElixirScript.Core.js',
      format: 'es',
    },
    plugins,
  })
  .then(bundle => {
    bundle.write({
      format: 'es',
      file: 'priv/build/es/ElixirScript.Core.js',
      sourcemap: 'inline',
    })
  })

rollup
  .rollup({
    input: 'priv/testrunner/vendor.js',
    output: {
      file: 'priv/testrunner/vendor.build.js',
      format: 'es',
    },
    plugins,
  })
  .then(bundle => {
    bundle.write({
      format: 'es',
      file: 'priv/testrunner/vendor.build.js',
    })
  })
