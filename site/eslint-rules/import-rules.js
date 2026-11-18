export default {
  meta: {
    type: 'layout',
    fixable: 'code',
    schema: [],
    messages: {
      sortImports:
        'Imports should be grouped (packages → absolute → relative) and sorted by last-line length within each group.',
    },
  },
  create(context) {
    return {
      Program(node) {
        const sourceCode = context.sourceCode;
        const imports = node.body.filter(n => n.type === 'ImportDeclaration');
        if (imports.length < 2) return;

        // Classify each import into a group
        const getGroup = importNode => {
          const source = importNode.source.value;
          if (source.startsWith('.')) return 2; // relative
          if (/^[A-Z]/.test(source)) return 1; // absolute (capital letter)
          return 0; // package
        };

        // Sort comparator: by last line length, alphabetical tiebreaker
        const lastLineLength = n => {
          const text = sourceCode.getText(n);
          const lines = text.split('\n');
          return lines[lines.length - 1].length;
        };

        const sortWithinGroup = arr =>
          [...arr].sort((a, b) => {
            const aLen = lastLineLength(a);
            const bLen = lastLineLength(b);
            if (aLen !== bLen) return aLen - bLen;
            return sourceCode.getText(a).localeCompare(sourceCode.getText(b));
          });

        // Build expected order: group 0, then 1, then 2, each sorted by length
        const grouped = [[], [], []];
        for (const imp of imports) {
          grouped[getGroup(imp)].push(imp);
        }

        const sortedGroups = grouped.filter(g => g.length > 0).map(sortWithinGroup);

        const sortedFlat = sortedGroups.flat();

        // Check if anything changed
        const isOutOfOrder = imports.some((imp, i) => imp !== sortedFlat[i]);

        // Check if blank lines between groups are correct
        let needsBlankLineFix = false;
        for (let i = 1; i < imports.length; i++) {
          const prevGroup = getGroup(imports[i - 1]);
          const currGroup = getGroup(imports[i]);
          const linesBetween = imports[i].loc.start.line - imports[i - 1].loc.end.line;

          if (prevGroup !== currGroup && linesBetween <= 1) needsBlankLineFix = true;
          if (prevGroup === currGroup && linesBetween > 1) needsBlankLineFix = true;
        }

        if (!isOutOfOrder && !needsBlankLineFix) return;

        context.report({
          node: imports[0],
          messageId: 'sortImports',
          fix(fixer) {
            const firstNode = imports[0];
            const lastNode = imports[imports.length - 1];
            const range = [firstNode.range[0], lastNode.range[1]];

            const newText = sortedGroups
              .map(group => group.map(n => sourceCode.getText(n)).join('\n'))
              .join('\n\n');

            return fixer.replaceTextRange(range, newText);
          },
        });
      },
    };
  },
};
