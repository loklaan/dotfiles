# Using Skills

## View Available Skills

Ask Claude directly:
```
What Skills are available?
```

Or check the filesystem:
```bash
# Personal Skills
ls ~/.claude/skills/

# Project Skills
ls .claude/skills/

# View a specific Skill's content
cat ~/.claude/skills/my-skill/SKILL.md
```

## Test a Skill

Test by asking questions matching your description:
```
Can you help me create a renderer for this content block?
```

Claude autonomously decides to use the Skill—no explicit invocation needed.

## Sharing Skills with Your Team

**Via Project Repository:**
1. Create a project Skill in `.claude/skills/`
2. Commit to git and push
3. Team members automatically get the Skill when pulling

**Via Plugin:**
1. Create a plugin with Skills in the `skills/` directory
2. Add to marketplace
3. Team members install the plugin

## Debugging Skills

### Common Issues

**Claude doesn't use the Skill:**
- **Make description specific**—include both what it does and when to use it (see writing-skills.md "Writing the Description")
- **Verify file path**—check `~/.claude/skills/skill-name/SKILL.md` exists
- **Check YAML syntax**—ensure valid frontmatter with proper indentation
- **View errors**—run `claude --debug`

**Multiple Skills conflict:**
Use distinct trigger terms in descriptions to help Claude choose correctly.

## Updating and Removing Skills

**Update**: Edit SKILL.md directly; changes take effect on next Claude Code restart

**Remove**:
```bash
# Personal
rm -rf ~/.claude/skills/my-skill

# Project
rm -rf .claude/skills/my-skill
git commit -m "Remove unused Skill"
```
