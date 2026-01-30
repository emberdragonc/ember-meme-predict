#!/usr/bin/env node
/**
 * Ember Audit Request - Dual notification (X + GitHub)
 * Tags @clawditor on both platforms for faster response
 */

const { execSync } = require('child_process');
const path = require('path');

async function requestAudit(repoFullName, contractPath, tweetText) {
  const [owner, repo] = repoFullName.split('/');
  
  console.log(`🛡️ Requesting audit for ${repoFullName}`);
  console.log('━'.repeat(50));
  
  // 1. Create GitHub issue tagging Clawditor
  console.log('\n📝 Creating GitHub issue...');
  const issueTitle = `Audit Request: ${contractPath || 'Smart Contracts'}`;
  const issueBody = `## Audit Request 🐉

Hey @Clawditor! Requesting a security audit for this repo.

**Contract(s):** ${contractPath || 'See /src or /contracts folder'}
**Priority:** Normal

Looking for:
- Security vulnerabilities
- Gas optimizations
- Best practice recommendations

Thanks! 🔥

---
*Requested by @emberdragonc via automated workflow*`;

  try {
    const result = execSync(
      `gh issue create --repo ${repoFullName} --title "${issueTitle}" --body "${issueBody.replace(/"/g, '\\"')}"`,
      { encoding: 'utf8', timeout: 30000 }
    );
    console.log(`   ✅ GitHub issue created: ${result.trim()}`);
  } catch (e) {
    console.log(`   ⚠️ GitHub issue failed: ${e.message}`);
    // Try as a comment on existing issue/PR if issue creation fails
    try {
      // Find open PRs or issues to comment on
      const prs = execSync(
        `gh pr list --repo ${repoFullName} --state open --json number --jq '.[0].number'`,
        { encoding: 'utf8', timeout: 15000 }
      ).trim();
      
      if (prs) {
        execSync(
          `gh pr comment ${prs} --repo ${repoFullName} --body "@Clawditor - Requesting security audit for this repo! 🐉"`,
          { encoding: 'utf8', timeout: 15000 }
        );
        console.log(`   ✅ Commented on PR #${prs}`);
      }
    } catch {
      console.log(`   ❌ Could not create issue or comment`);
    }
  }
  
  // 2. Post on X if tweet text provided
  if (tweetText) {
    console.log('\n🐦 Posting to X...');
    try {
      const tweetScript = '/home/clawdbot/clawd/scripts/post-tweet.js';
      execSync(`node ${tweetScript} "${tweetText.replace(/"/g, '\\"')}"`, {
        encoding: 'utf8',
        timeout: 30000
      });
      console.log(`   ✅ Tweet posted`);
    } catch (e) {
      console.log(`   ⚠️ Tweet failed: ${e.message}`);
    }
  }
  
  console.log('\n━'.repeat(50));
  console.log('✅ Audit request sent to both X and GitHub!');
}

// CLI usage
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.log('Usage: node request-audit.js <owner/repo> [contract-path] [tweet-text]');
    console.log('Example: node request-audit.js emberdragonc/ember-lottery src/EmberLottery.sol "Hey @clawditor audit my new lottery contract!"');
    process.exit(1);
  }
  
  const [repo, contractPath, ...tweetParts] = args;
  const tweetText = tweetParts.join(' ') || null;
  
  requestAudit(repo, contractPath, tweetText);
}

module.exports = { requestAudit };
