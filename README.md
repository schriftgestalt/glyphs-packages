# Glyphs Packages

Repository for collecting all available plug-ins for Glyphs. What is registered here will end up in *Window > Plugin Manager*.

![Window](https://github.com/schriftgestalt/glyphs-packages/blob/master/images/Screenshot.png?raw=true)

### Format

Separate multiple entries with commas. Best place to put it is right behind the closing curly brace `}` at the end of the entry.

#### Required Fields

- **name:** the file name of the plug-in in the repository, including the dot suffix.
- **url:** the URL to the repository. On GitHub, this will be `https://github.com/username/repositoryname`.
- **description:** a short text explaining the plug-in. It supports basic Markdown. *Attention:* Do not use linebreaks here, but keep the text on a single line. If you want a linebreak in your description, use `\n` instead.

#### Optional Fields

- **screenshot:** the URL to an image or screenshot illustrating the plug-in.
- **minVersion:** the minimum Glyphs version required for running the plug-in. Use the three-digit build number, e.g., `895`.
- **maxVersion:** build number of the last version of Glyphs capable of running the plug-in. This can be used for older versions of the plug-in.

#### Example

	{
		name = "Noodler.glyphsFilter";
		url = "https://github.com/mekkablue/Noodler";
		description = "*Filter > Noodler* turns monolines of all selected glyphs into noodles.";
		screenshot = "https://raw.githubusercontent.com/mekkablue/Noodler/master/Noodler.png";
		minVersion = 895;
	},
	{
		name = "Noodler_OLD.glyphsFilter";
		url = "https://github.com/mekkablue/Noodler";
		description = "This is an old version of Noodler. Consider updating Glyphs to use the latest version of the plug-in.";
		screenshot = "https://raw.githubusercontent.com/mekkablue/Noodler/master/Noodler.png";
		maxVersion = 894;
	}


### How to add your own plug-ins

To add your own plug-in, fork this repository, add your plug-in to the `packages.plist` and send a pull request.

### Credits

The plug-in is based on the Xcode plug-in manager [Alcatraz](http://alcatraz.io).