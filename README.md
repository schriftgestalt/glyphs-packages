# Glyphs Packages
Repository to collect all available plugins for Glyphs. 
![Window](https://github.com/schriftgestalt/glyphs-packages/blob/master/images/Screenshot.png?raw=true)

### Format

#### Required Fields

- name: the file name of the plugin
- url: the url to the repository
- description: a short text explaining the plugin. It supports basic markdown. 

#### Optional Fields

- screenshot: the url to a image/screenshot illustrating the plugin
- minVersion: the min required Glyphs version. Use the three digit number.
- maxVersion: for the last version of Glyphs that can run the plugin. That can be used for older versions of the plugin. 


### How to add your own plugins

To add your own plugin, fork this repository, add your plugin to the `packages.plist` and send a pull request.

### Credits

The plugin is based on the Xcode-plugin manager [Alcatras](http://alcatraz.io).