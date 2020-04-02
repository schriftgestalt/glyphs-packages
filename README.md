[![Build Status](https://travis-ci.org/schriftgestalt/glyphs-packages.svg?branch=master)](https://travis-ci.org/schriftgestalt/glyphs-packages)

# Glyphs Packages

Repository for collecting all available plug-ins for Glyphs. What is registered here will end up in *Window > Plugin Manager*. If you have written a plug-in and want to share it with the community, consider adding it to the `.plist` file.

![Window](https://github.com/schriftgestalt/glyphs-packages/blob/master/images/Screenshot.png?raw=true)

### Format

Separate multiple entries with commas. Best place to put it is right behind the closing curly brace `}` at the end of the entry.

#### Required Fields

- **name:** the file name of the plug-in in the repository, including the dot suffix. The name until the dot will be used as title in the Plugin Manager window, unless *titles* are explicitly set (see below).
- **url:** the URL to the repository. On GitHub, this will be `https://github.com/username/repositoryname`.
- **descriptions:** a language-specific short text explaining the plug-in. It supports basic Markdown (`*italic* **bold** [text](https://link.url)`). *Attention:* Do not use linebreaks here, but keep the text on a single line. If you want a linebreak in your description, use `\n` instead. Differentiate between languages with one of these abbreviations:

  * `cs`: Czech
  * `de`: German
  * `en`: English
  * `es`: Spanish
  * `fr`: French
  * `it`: Italian
  * `ja`: Japanese
  * `ko`: Korean
  * `pt`: Portuguese
  * `ru`: Russian
  * `tr`: Turkish
  * `zh_CN`: Chinese (simplified, mainland China)
  * `zh-Hant`: Chinese (traditional, Taiwan)

```plist
descriptions = {
	en = "*Filter > Insert Inflections* inserts nodes on all inflections of all selected glyphs. This is useful for monoline workflows, where inflected paths need to be expanded to a closed stroke; and for conversion into TrueType outlines.";
	de = "*Filter > Inflektionspunkte einfügen* fügt Punkte an den Wendestellen aller Kurven aller ausgewählter Glyphen ein. Nützlich für lineare Strich-Designs (»Monolines«) mit offenen Skelett-Pfaden, die erst zu Flächen erweitert werden müssen (exakteres Expansionsergebnis); und vor der Konvertierung in TrueType-Pfade.";
};
```

#### Optional Fields

- **titles:** the language-specific human-readable name, if different from the file name of the plug-in. Useful for storing a name containing spaces when the filename does not. For languages, see the list above.

```plist
	titles = {
		en = "Broad Nibber";
		de = "Breitfederzeichner";
	};
```

- **screenshot:** the URL to an image or screenshot illustrating the plug-in.
- **minVersion:** the minimum Glyphs version required for running the plug-in. Use the three- or four-digit build number as displayed between parentheses next to the version string in *Glyphs > About Glyphs,* e.g., `895`.
- **maxVersion:** build number of the last version of Glyphs capable of running the plug-in. This can be used for older versions of the plug-in.
- **minGlyphsVersion:** minimum Glyphs version, use dumb quotes for the value, e.g. `"2.6.1"`.
- **maxGlyphsVersion:** maximum Glyphs version, use dumb quotes for the value, e.g. `"2.6.1"`.
- **minSystemVersion:** minimum macOS version, use dumb quotes for the value, e.g. `"10.11"`. Useful if you use a (Py)ObjC method that has been introduced or deprecated in a certain macOS version.
- **maxSystemVersion:** maximum macOS version, use dumb quotes for the value, e.g. `"10.12"`. Useful if you use a (Py)ObjC method that has been introduced or deprecated in a certain macOS version.

#### Conventions

* Use emphasis (text surrounded by by single asterisks `*` or underscores `_`) for text that appears in the UI, like a menu command. E.g., *File > Save.*
* Use code (text surrounded by single backticks `` ` ``) for text entered by the user, e.g. Python commands like `Glyphs.defaults["x"]=y`.
* Do not stylize keyboard commands. Capitalise key names (Cmd, Ctrl, Shift, Opt), and use dashes between keys, e.g. Cmd-Shift-B.

#### Example

	{
		titles = {
			en = "Insert Inflections";
		};
		name = "Noodler.glyphsFilter";
		url = "https://github.com/mekkablue/Noodler";
		descriptions = {
			en = "*Filter > Noodler* turns monolines of all selected glyphs into noodles.";
		};
		screenshot = "https://raw.githubusercontent.com/mekkablue/Noodler/master/Noodler.png";
		minVersion = 895;
	},
	{
		titles = {
			en = "Noodler (outdated version)";
			de = "Nudler (veraltete Version)";
		}
		name = "Noodler_OLD.glyphsFilter";
		url = "https://github.com/mekkablue/Noodler";
		descriptions = {
			en = "This is an old version of Noodler. Consider updating Glyphs to use the latest version of the plug-in.";
			de = "Diese Version von Nudler ist veraltet. Bitte aktualisieren Sie Glyphs, umd die neueste Version nutzen zu können.";
		};
		screenshot = "https://raw.githubusercontent.com/mekkablue/Noodler/master/Noodler.png";
		maxVersion = 894;
	}


### How to add your own plug-ins

To add your own plug-in, fork this repository, add your plug-in to the `packages.plist` and send a pull request.

Run the command `plutil -lint packages.plist` in a Terminal window to check for syntax errors. It should print the following message (the `:; ` is just the Terminal shell prompt in this example):
```
:; plutil -lint packages.plist
packages.plist: OK
```

### Credits

The plug-in is based on the Xcode plug-in manager [Alcatraz](http://alcatraz.io).