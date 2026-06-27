# GoDEx
Project to re-implement Deus Ex into Godot. (Not a source port since Unreal Engine 1 never had its source code publically released)

## Why?
Deus Ex is my favourite PC game to this day, and since I'm making a game in Godot that is also an immersive sim I thought it'd be cool to see if it could be possible to move Deus Ex into
the engine by reimplementing its mechanics. I also [expanded on a GDExtension plugin that plays modtracker music](https://github.com/PeterD23/godot-openmpt-controller) so
if nothing else I could at least get the music working!

## Can this be used for Unreal/Unreal Tournament/Duke Nukem Forever?
This isn't designed to be a generic Unreal Engine 1 interpreter, for something like that I'd check out [Surreal 98](https://store.steampowered.com/app/3043880/Surreal_98)
but you can also fork this repo as well, since the parser should in theory work on Unreal maps as well.

## Current Roadmap to next version
-  [x] Open a T3D File to parse
-  [x] Brush Actors
-  [ ] Light Actors
-  [ ] Ambient Sound Actors
-  [ ] Named Class Actors (Meshes, NPCs etc)
-  [ ] PathNode Actors
-  [ ] PatrolPoint Actors

## Usage
Clone the repo and open with Godot.
Maps can be generated using the T3DMapGenerator class node. Requires a t3d file so you'll need to convert your .dx maps using either UCC or Unreal Editor. I'm intending on having
a conversion processing menu later on that can point to your Deus Ex installation directory and then automatically generate scenes by doing conversion of maps from .dx to .t3d

## Current Issues
CSG line-up on subtractions isn't great so a lot of doorways will appear blocked off and some larger volumes won't intersect correctly on the first pass:

<img width="1383" height="940" alt="image" src="https://github.com/user-attachments/assets/9db47ed2-e7de-47f9-bf30-a3a0a0be0508" />

With the help of another user on a game dev discord I'm part of (shoutout to [Portponky](https://github.com/Portponky))
there's an editor button on the node that can try to align the subtractions up a bit better. It does take a long time to process though and still doesn't quite catch all the subtractions,
but given some of the subtraction volumes are completely off on the map like this cursed thing that is supposed to be the ceiling up the stairs
<img width="235" height="121" alt="image" src="https://github.com/user-attachments/assets/96e33229-3af7-4b9d-b948-d32b5e8cf73f" />
there is a lot of work to be done on getting the geometry to work.

## Contributing
Contributors are welcome, any mappers in the DXHQ Discord who have a better understanding of the Unreal Engine brush system, your knowledge would be greatly appreciated if you have the time to do so!
I get the thematic relevance of AI in the game translating to today but please don't put any LLM generated code into this project. Feel free to fork it but this project is a intriguing problem that I'd
like to solve and I think using LLMs to bypass that takes away from the satisfaction.

Also this should be obvious but dont commit any copyrighted material. This includes t3ds, converted meshes, texture data etc. Any data generated should be kept local to the project.
