# Resource Map Markers

This is a mod for the game [Factorio](https://www.factorio.com/). It can be downloaded from the [Factorio Mod Portal](https://mods.factorio.com/mod/sonaxaton-resource-map-markers).

## Description

This mod will automatically create markers on your map for resource patches. The markers use the icon of the resource and include the name and amount of resource in the patch. For normal resources, the total amount is displayed. For infinite resources like oil, the average yield is displayed. There are mod settings to hide the name or amount if you want. Should work with all modded resources as well.

As the map is revealed, new chunks are scanned for resources in a very efficient way to add and update map markers. You can also edit/remove the markers yourself if you want, or use commands to control them:

* `/resource-map-markers mark` - Clear all existing markers added by the mod then search all chunks on all surfaces for resources and add markers for them.
* `/resource-map-markers clear` - Clear all existing markers added by the mod.
* `/resource-map-markers hide` - Hide resource markers. The markers can be shown again without scanning chunks.
* `/resource-map-markers show` - Show any hidden resource markers without scanning chunks. Will also restore any markers you may have deleted manually.
* `/resource-map-markers mark-here` - Search your current chunk for resources and add markers for them.

I made this mod as an alternative to [Resource Map Label Marker](https://mods.factorio.com/mod/resourceMarker) because I didn't like how that mod revealed new chunks to mark resources. My mod will never reveal new chunks or mark resources on chunks outside of ones that are already visible. I also just thought it would be fun to learn more about modding by implementing this myself. I ended up with a very different approach than that mod which should be very efficient even for large maps.

## Known issues

* Oil-like resource patches that are nearby aren't grouped together properly. I put in a [modding API request](https://forums.factorio.com/viewtopic.php?f=28&t=84405) to get access to the property needed to fix this, and will update when that's fulfilled.

## Removing the mod

If you decide to remove the mod from an existing save, you might want to run the `/resource-map-markers clear` command first to clear any markers it may have added.
