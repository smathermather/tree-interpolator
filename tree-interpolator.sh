#!/bin/sh

# Calculate Tree height using pdal pipeline
# replace the z value with a height value
# allows for floating point z value

# -----------------------------------------------------
# Tree height calculations
# 
# Start with las or laz files
# End with text file with X, Y, and Tree Height
# -----------------------------------------------------

#[
#    "input.las",
#    {
#        "type":"filters.hag_delaunay"
#    },
#    {
#        "type":"writers.las",
#        "filename":"tree_height.laz",
#        "extra_dims":"HeightAboveGround=float32"
#    }
#]
echo "	Calculating Tree Height..."
pdal pipeline height.json


# Eliminate all but tall vegetation (class 5)

#[
#    "tree_height.laz",
#    {
#                "type":"filters.expression",
#                "expression":"((HeightAboveGround > 0) && Classification == 5)"
#    },
#    {
#        "type":"writers.las",
#        "filename":"tree_height_only.laz",
#        "extra_dims":"HeightAboveGround=float32"
#    }
#]

echo "		 								Eliminating non-veg points..."
pdal pipeline class.json

#[
#    {
#        "type":"readers.las",
#        "filename":"tree_height_only.laz"
#    },
#    {
#        "type":"writers.text",
#        "format":"csv",
#        "order":"X,Y,HeightAboveGround",
#        "keep_unspecified":"false",
#        "delimiter":" ",
#        "filename":"tree_height_only.txt",
#        "write_header":"false"
#    }
#]

echo "
  Write out text file..."
pdal pipeline text.json

# -----------------------------------------------------
# Prepare Include Files for Povray
# -----------------------------------------------------

# Count number of tree height points
numlines=`more tree_height_only.txt | wc -l`
echo " 										$numlines points in resultant las."

# Build include files of tree locations and heights for PovRay rendering
# Tree locations are fixed at height of 0

# Write tree coordinate array header
echo "#declare tree_coords = array["$numlines"]{" > tree_height_coords.inc

# Write X, 0, Y locations
more tree_height_only.txt | grep -v ' 0' | awk '{print "<" $1 ", 0, " $2 ">" };' >> tree_height_coords.inc

# Write tree height array header
echo "} #declare tree_height = array["$numlines"]{" >> tree_height_coords.inc

# Write tree heights
more tree_height_only.txt | grep -v ' 0' |  awk '{ print $3 "," };' >> tree_height_coords.inc
echo '}' >> tree_height_coords.inc

# -----------------------------------------------------
# Prepare Scene Extent Variables for Povray
# using pdal tindex and ogrinfo
# -----------------------------------------------------

# Calculate extent of point cloud using pdal tindex
pdal tindex create --tindex tree_height_boundary.sqlite --filespec tree_height_only.laz -f SQLite

# From index file we'll calculate scene extent and center
bb=`ogrinfo -ro -al -so -geom=NO tree_height_boundary.sqlite | grep Extent | tr '(' ' ' | tr ')' ' ' | tr ',' ' '`
minx=`echo $bb | awk '{print $2};'`
miny=`echo $bb | awk '{print $3};'`
maxx=`echo $bb | awk '{print $5};'`
maxy=`echo $bb | awk '{print $6};'`

width=`echo "$maxx - $minx" | bc`
height=`echo "$maxy - $miny" | bc`

# Calculate center of point cloud
centerx=`echo "($maxx + $minx) / 2" | bc`
centery=`echo "($maxy + $miny) / 2" | bc`

# Set camera size, pixel size and image size 
camera_size=5000
pixel_size=1
image_size=`echo "scale=20; $camera_size / $pixel_size" | bc`

ulx=`echo "scale=20; $centerx - $camera_size / 2" | bc`
uly=`echo "scale=20; $centery + $camera_size / 2" | bc`

# -----------------------------------------------------
# Write the pov file for rendering
# -----------------------------------------------------

# Using what we know, let's build the pov file for rendering
echo "//Set the center of image" > render.pov
echo "\n" >> render.pov
echo "#version 3.6;" >> render.pov
echo "#declare scene_center_x=$centerx;" >> render.pov
echo "#declare scene_center_y=$centery;" >> render.pov

echo "//Include locations and heights for trees." >> render.pov
echo '#include "tree_height_coords.inc"' >> render.pov

echo "#declare Camera_Size = $camera_size;" >> render.pov

more treepov.inc >> render.pov

# -----------------------------------------------------
# Time to render our scene!
# -----------------------------------------------------

povray +Irender.pov +Orender.png +FN16 +W$image_size +H$image_size +A +D

# Now time to create a world file to georeference

echo $pixel_size > render.pgw
echo 0 >> render.pgw
echo 0 >> render.pgw
echo -$pixel_size >> render.pgw
echo $ulx >> render.pgw
echo $uly >> render.pgw
