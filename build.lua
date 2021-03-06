local arrr = require 'arrr'
local restia = require 'restia'
local shapeshift = require 'shapeshift'

local params do
	local is = shapeshift.is
	local parse = arrr {
		{ "Output directory", "--output", "-o", 'directory' };
		{ "Input directory", "--input", "-i", 'directory' };
		{ "Copy directory", "--copy", "-c", 'directory', 'repeatable' };
		{ "Delete everything first", "--delete", "-d" };
		{ "Render unpublished posts too", "--unpublished" };
	}
	local validate = shapeshift.table {
		output = shapeshift.default("out", is.string);
		input = shapeshift.default(".", is.string);
		copy = shapeshift.default({}, shapeshift.all{
			is.table,
			shapeshift.each(is.string)
		});
		delete = shapeshift.default(false, shapeshift.is.boolean);
		unpublished = shapeshift.maybe(shapeshift.is.boolean);
	}
	params = select(2, assert(validate(parse{...})))
end

package.loaded.i18n = restia.config.yaml('i18n/de')

local config = restia.config.bind('config', {
	(require 'restia.config.readfile');
	(require 'restia.config.lua');
	(require 'restia.config.yaml');
})
package.loaded.config = config

local templates = restia.config.bind('templates', {
	(require 'restia.config.skooma');
	(require 'restia.config.moonhtml');
})
package.loaded.templates = templates

local function render_post(file)
	local post = restia.config.post(from)

	restia.utils.mkdir(to:gsub("[^/]+$", ""))
	local outfile = assert(io.open(to, 'wb'))
	outfile:write(body)
	outfile:close()
end

local posts = {}
package.loaded.posts = posts

local tree = {}

for i, path in ipairs(params.copy) do
	restia.utils.deepinsert(tree, restia.utils.fs2tab(path), restia.utils.readdir(path))
end

local validate_head do
	local is = shapeshift.is
	validate_head = shapeshift.table {
		__extra = 'keep';
		title = is.string;
		date = shapeshift.matches("%d%d%d%d%-%d%d%-%d%d");
		file = is.string;
		publish = is.boolean;
	}
end

local function parsedate(date)
	local year, month, day = date:match("(%d+)%-(%d+)%-(%d+)")
	return os.time {
		year = tonumber(year);
		month = tonumber(month);
		day = tonumber(day);
	}
end

local tags = {}
local function tag(article, tagname)
	if not tags[tagname] then
		tags[tagname] = {}
	end
	table.insert(tags[tagname], article)
end

-- Load Posts
for file in restia.utils.files(params.input, "%.md$") do
	post = restia.config.post(file)
	post.head.file = file

	do
		local ok, msg = validate_head(post.head, "Post head")
		if not ok then
			error("validating head "..file..": "..msg)
		end
	end

	if type(post.head.tags)=="string" then
		local tags = {}
		for tag in post.head.tags:gmatch('[%a_-]+') do
			table.insert(tags, tag)
		end
		post.head.tags = tags
	end
	if post.head.tags then
		for tagname in ipairs(post.head.tags) do
			tag(post, tagname)
		end
	end

	post.head.timestamp = parsedate(post.head.date)

	post.head.slug = post.head.title
		:gsub(' ', '_')
		:lower()
		:gsub('[^a-z0-9-_]', '')

	post.head.uri = string.format("/%s/%s.html", post.head.date:gsub("%-", "/"), post.head.slug)
	post.path = restia.utils.fs2tab(post.head.uri)

	if post.head.publish or params.unpublished then
		table.insert(posts, post)
	end
end

table.sort(posts, function(a, b)
	return a.head.timestamp > b.head.timestamp
end)

-- TODO: Index page and stuff

-- Render Posts
for idx, post in ipairs(posts) do
	local template if post.head.template then
		template = templates[post.head.template]
	elseif templates.article then
		template = templates.article
	end

	local body if template then
		body = restia.utils.deepconcat(template(post.body, post.head))
	else
		body = post.body
	end

	restia.utils.deepinsert(tree, post.path, body)
end

if params.delete then
	print("Deleting:  "..params.output)
	restia.utils.delete(params.output)
end

restia.utils.builddir(params.output, tree)
