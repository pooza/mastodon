module.exports = {
  extends: ['stylelint-config-standard-scss'],
  ignoreFiles: [
    'app/javascript/styles/mastodon/reset.scss',
    'coverage/**/*',
    'node_modules/**/*',
    'public/assets/**/*',
    'public/packs*/**/*',
    'vendor/**/*',
  ],
  reportDescriptionlessDisables: true,
  reportInvalidScopeDisables: true,
  reportNeedlessDisables: true,
  rules: {
    'at-rule-empty-line-before': null,
    'color-function-notation': null,
    'color-function-alias-notation': null,
    'declaration-block-no-redundant-longhand-properties': null,
    'no-descending-specificity': null,
    'no-duplicate-selectors': null,
    'number-max-precision': 8,
    'property-no-vendor-prefix': null,
    'selector-class-pattern': null,
    'selector-id-pattern': null,
    'value-keyword-case': null,
    'value-no-vendor-prefix': null,
    'custom-property-pattern': [
      '^_?[a-z]([a-z0-9])*(-[a-z0-9]+)*$',
      {
        message: (name) =>
          `Expected custom property name "${name}" to be kebab-case (optional leading underscore allowed)`,
      },
    ],

    'scss/dollar-variable-empty-line-before': null,
    'scss/no-global-function-names': null,

    // Fork policy (#906): never adopt text-transform: uppercase / capitalize.
    // Mechanical capitalization can change a word's meaning and loses information.
    // upstream uses these frequently; we neutralize each to `none` per release and
    // this rule prevents new occurrences from slipping in on upstream merges.
    'declaration-property-value-disallowed-list': [
      {
        'text-transform': ['/^uppercase$/i', '/^capitalize$/i'],
      },
      {
        message: (property, value) =>
          `Fork policy (#906): "${property}: ${value}" is disallowed. Use "none" instead of uppercase/capitalize.`,
      },
    ],
  },
  overrides: [
    {
      files: ['app/javascript/styles/entrypoints/mailer.scss'],
      rules: {
        'property-no-unknown': [
          true,
          {
            ignoreProperties: ['/^mso-/'],
          },
        ],
      },
    },
    {
      files: [
        'app/javascript/**/*.module.scss',
        'app/javascript/**/*.module.css',
      ],
      rules: {
        'selector-pseudo-class-no-unknown': [
          true,
          { ignorePseudoClasses: ['global'] },
        ],

        'property-no-unknown': [
          true,
          {
            ignoreProperties: ['composes'],
          },
        ],
      },
    },
  ],
};
