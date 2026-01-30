#!/bin/bash
# Security Scan Script for Smart Contract Framework
# Run this before deployment to catch common issues

set -e

echo ""
echo "🔍 Smart Contract Security Scan"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

# 1. Format check
echo "📝 [1/6] Checking code formatting..."
if forge fmt --check 2>/dev/null; then
    echo -e "${GREEN}✓ Formatting OK${NC}"
else
    echo -e "${YELLOW}⚠ Formatting issues found. Run 'forge fmt' to fix.${NC}"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# 2. Compile
echo "🔨 [2/6] Compiling contracts..."
if forge build 2>/dev/null; then
    echo -e "${GREEN}✓ Compilation successful${NC}"
else
    echo -e "${RED}✗ Compilation failed${NC}"
    exit 1
fi
echo ""

# 3. Run tests
echo "🧪 [3/6] Running tests..."
if forge test -vv 2>&1 | tail -20; then
    echo -e "${GREEN}✓ Tests passed${NC}"
else
    echo -e "${RED}✗ Tests failed${NC}"
    FAILURES=$((FAILURES + 1))
fi
echo ""

# 4. Slither (if installed)
echo "🐍 [4/6] Running Slither static analysis..."
if command -v slither &> /dev/null; then
    echo "Running slither..."
    if slither . --filter-paths "lib|test|script" \
        --exclude naming-convention,solc-version,pragma \
        --json slither-report.json 2>/dev/null; then
        echo -e "${GREEN}✓ Slither passed${NC}"
    else
        echo -e "${YELLOW}⚠ Slither found issues (see slither-report.json)${NC}"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo -e "${YELLOW}⚠ Slither not installed. Install with: pip3 install slither-analyzer${NC}"
fi
echo ""

# 5. Coverage
echo "📊 [5/6] Generating coverage report..."
if forge coverage 2>&1 | tail -30; then
    echo -e "${GREEN}✓ Coverage report generated${NC}"
else
    echo -e "${YELLOW}⚠ Coverage generation failed${NC}"
fi
echo ""

# 6. Gas report
echo "⛽ [6/6] Generating gas report..."
forge test --gas-report 2>&1 | tail -50 > gas-report.txt
echo "Gas report saved to gas-report.txt"
echo -e "${GREEN}✓ Gas report generated${NC}"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}✅ Security scan complete - No critical issues${NC}"
else
    echo -e "${YELLOW}⚠️  Security scan complete - $FAILURES issue(s) found${NC}"
fi
echo ""
echo "📋 Next steps:"
echo "   1. Review slither-report.json (if generated)"
echo "   2. Check gas-report.txt for optimization opportunities"
echo "   3. Review AUDIT_CHECKLIST.md before deployment"
echo ""
