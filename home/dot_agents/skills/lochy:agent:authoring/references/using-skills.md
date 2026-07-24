# Using Skills

## View Available Skills

Ask the active coding assistant directly:
```
What skills are available?
```

Or check the filesystem:
```bash
# Personal shared skills
ls ~/.agents/skills/

# Project shared skills
ls .agents/skills/

# View a specific skill's content
cat ~/.agents/skills/my-skill/SKILL.md
```

## Test a Skill

Test by asking questions matching your description:
```
Can you help me create a renderer for this content block?
```

The assistant may autonomously decide to use the skill when its description matches. If the tool does not discover `.agents/` directly, point it there from `AGENTS.md`, `CLAUDE.md`, or the vendor-specific config.

## Sharing Skills with Your Team

**Via Project Repository:**
1. Create a project skill in `.agents/skills/`
2. Commit to git and push
3. Team members automatically get the Skill when pulling

**Via Plugin:**
1. Create a plugin with Skills in the `skills/` directory
2. Add to marketplace
3. Team members install the plugin

## Debugging Skills

### Common Issues

**The assistant doesn't use the skill:**
- **Make description specific**—include both what it does and when to use it (see writing-skills.md "Writing the Description")
- **Verify file path**—check `~/.agents/skills/skill-name/SKILL.md` or `.agents/skills/skill-name/SKILL.md` exists
- **Check YAML syntax**—ensure valid frontmatter with proper indentation
- **View errors**—use the active tool's debug mode

**Multiple Skills conflict:**
Use distinct trigger terms in descriptions to help the assistant choose correctly.

## Updating and Removing Skills

**Update**: Edit `SKILL.md` directly; changes take effect on the next tool restart or skill reload.

**Remove**:
```bash
# Personal
rm -rf ~/.agents/skills/my-skill

# Project
rm -rf .agents/skills/my-skill
git commit -m "Remove unused Skill"
```
