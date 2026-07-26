import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "lib/**", // Ignore built files.
      "generated/**", // Ignore generated files.
    ],
  },
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    languageOptions: {
      globals: globals.node,
      sourceType: "module",
    },
    rules: {
      "quotes": ["error", "double"],
      "indent": ["error", 2],
      // Kept from the retired eslint-config-google preset so the 80-column
      // discipline the sources were written to still holds.
      "max-len": ["error", {
        code: 80,
        tabWidth: 2,
        ignoreUrls: true,
        ignoreComments: false,
        ignoreRegExpLiterals: true,
        ignoreStrings: true,
        ignoreTemplateLiterals: true,
      }],
    },
  },
);
