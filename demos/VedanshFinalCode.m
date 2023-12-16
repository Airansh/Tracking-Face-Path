addpath('../Mex');
clear all
close all

kz = KinZ('720p', 'unbinned', 'nfov', 'imu_on');

% images sizes
depthWidth = kz.DepthWidth; 
depthHeight = kz.DepthHeight; 
outOfRange = 2000;
colorWidth = kz.ColorWidth; 
colorHeight = kz.ColorHeight;

% Threshold for determining if a face is the same as the tracked one
threshold = 50; % Adjust this value as needed

% Color image is to big, let's scale it down
colorScale = 1.0;

% Create matrices for the images
depth = zeros(depthHeight,depthWidth,'uint16');
infrared = zeros(depthHeight,depthWidth,'uint16');
color = zeros(colorHeight*colorScale,colorWidth*colorScale,3,'uint8');

% depth stream figure
f1 = figure;
h1 = imshow(depth,[0 outOfRange]);
ax1 = f1.CurrentAxes;
title(ax1, 'Depth Source')
colormap(ax1, 'Jet')
colorbar(ax1)

% color stream figure
f2 = figure;
h2 = imshow(color,[]);
ax2 = f2.CurrentAxes;
title(ax2, 'Color Source (press q to exit)');
set(f2,'keypress','k=get(f2,''currentchar'');'); % listen keypress

% infrared stream figure
f3 = figure;
h3 = imshow(infrared);
ax3 = f3.CurrentAxes;
title(ax3, 'Infrared Source');

% Load the face detection cascade object
faceDetector = vision.CascadeObjectDetector();

% Initialize the point tracker
pointTracker = vision.PointTracker("MaxBidirectionalError", 2);

% Create a video player for displaying the tracked video
videoPlayer = vision.VideoPlayer("Position", [100 100 [size(color, 2), size(color, 1)]+30]);

% Loop until pressing 'q' on any figure
k = [];
oldPoints = [];

% Hypothetical calibration parameters
depthScale = 0.001; % Conversion factor for depth to meters (millimeters to meters)
depthOffset = 200;  % Offset to correct for zero depth value

% Initialize an empty array to store the 3D points
path3D = [];

% Initialize the matrix for storing face coordinates
faceCoordMatrix = [];

% Add a flag to indicate if a face has been selected for tracking
faceSelected = false;
selectedFaceCenter = [];

isSpacebarPressed = false;

disp('Press q on color figure to exit')

while true
    % Get frames from Kinect and save them on underlying buffer
    validData = kz.getframes('color', 'depth', 'infrared', 'imu');
    
    if validData
        [depth, ~] = kz.getdepth;
        [color, ~] = kz.getcolor;
        [color2, ~] = kz.getcoloraligned;
        [infrared, ~] = kz.getinfrared;
        sensorData = kz.getsensordata;
        
        % Perform face detection
        bbox = step(faceDetector, color2);
        
        % Draw circles at the center of each detected face
        numFaces = size(bbox, 1);
        for i = 1:numFaces
            % Calculate the center of the current bounding box
            centerX = bbox(i, 1) + bbox(i, 3) / 2;
            centerY = bbox(i, 2) + bbox(i, 4) / 2;
            
            % Get the depth value at the center point
            depthValue = depth(round(centerY), round(centerX));
            
            % Convert depth value to distance in meters
            distance = (depthValue - depthOffset) * depthScale;
            
            % Adjust the size of the circle
            radius = min(bbox(i, 3), bbox(i, 4)) / 30; 

            % Draw a circle at the center
            bboxColorFrame = insertShape(color2, "circle", [centerX, centerY, radius], "LineWidth", 2, "Color", "red");
            bboxDepthFrame = insertShape(depth, "rectangle", bbox);
            
            % If the spacebar is currently pressed, record the first face
            if isSpacebarPressed && i == 1
                faceCoordMatrix = [faceCoordMatrix; centerX, centerY, distance];
            end
        end
        
        % Check if a face is already being tracked
        if faceSelected
            % Find the face that matches the selected face center
            matchedFaceIdx = findMatchingFace(bbox, selectedFaceCenter, threshold);
            if matchedFaceIdx > 0
                % Update tracking data with the matched face
                updateTrackingData(bbox(matchedFaceIdx, :), depth, depthOffset, depthScale, faceCoordMatrix);
            end
        else
            % If no face is being tracked, select the first detected face
            if ~isempty(bbox)
                selectedFaceCenter = [bbox(1, 1) + bbox(1, 3) / 2, bbox(1, 2) + bbox(1, 4) / 2];
                faceSelected = true;
                updateTrackingData(bbox(1, :), depth, depthOffset, depthScale, faceCoordMatrix);
            end
        end

        % Handle key presses
        if ~isempty(k)
            switch k
                case ' '
                    % Spacebar pressed
                    isSpacebarPressed = true;
                case 's'
                    % 's' pressed - stop spacebar tracking
                    isSpacebarPressed = false;
                case 'p'
                    % P pressed: Plot the trajectory
                    isSpacebarPressed = false;
                    if ~isempty(faceCoordMatrix)
                        % Filter points more than 50 cm away
                        validIndices = faceCoordMatrix(:, 3) <= 0.5; % 0.5 meters or 50 cm
                        filteredFaceCoordMatrix = faceCoordMatrix(validIndices, :);

                        figure;
                        plot3(filteredFaceCoordMatrix(:, 1), filteredFaceCoordMatrix(:, 2), filteredFaceCoordMatrix(:, 3), 'b.-');
                        xlabel('X');
                        ylabel('Y');
                        zlabel('Distance');
                        title('3D Path of Face Center within 50 cm');
                        grid on;
                    end
                case 'c'
                    % C pressed: Clear the faceCoordMatrix
                    isSpacebarPressed = false;
                    faceCoordMatrix = [];
                case 'q'
                    % Q pressed: Exit loop
                    break;
            end
            k = [];
        end

        % update color and depth figures
        bboxColorFrame = imresize(bboxColorFrame, colorScale);
        set(h2, 'CData', bboxColorFrame);
        set(h1, 'CData', bboxDepthFrame);
    end

    % If user presses 'q', exit loop
    if ~isempty(k)
        if strcmp(k, 'q'); break; end
        k = [];
    end

    pause(0.01)
end

% Close kinect object
kz.delete;
% Plot the 3D path using faceCoordMatrix
if ~isempty(faceCoordMatrix)
    figure;
    plot3(faceCoordMatrix(:, 1), faceCoordMatrix(:, 2), faceCoordMatrix(:, 3), 'b.-');
    xlabel('X');
    ylabel('Y');
    zlabel('Distance');
    title('3D Path of Face Center');
    grid on;
end


% Function to filter out noise from the face tracking data
function filteredData = filterNoise(faceData)
    % Define a threshold for distance deviation (adjust as necessary)
    distanceThreshold = 20; % example threshold in millimeters

    % Calculate the mean distance
    meanDistance = mean(faceData(:, 3));

    % Find indices of points within the distance deviation threshold
    validIndices = abs(faceData(:, 3) - meanDistance) < distanceThreshold;

    % Additional filter to remove points further than 1000 mm
    closeEnoughIndices = faceData(:, 3) <= 500;

    % Combine both filtering conditions
    finalIndices = validIndices & closeEnoughIndices;

    % Filter the data
    filteredData = faceData(finalIndices, :);
end


% Function to find the matching face based on center coordinates
function idx = findMatchingFace(bboxes, center, threshold)
    idx = 0;
    for i = 1:size(bboxes, 1)
        currentCenter = [bboxes(i, 1) + bboxes(i, 3) / 2, bboxes(i, 2) + bboxes(i, 4) / 2];
        if isclose(currentCenter, center, threshold)
            idx = i;
            break;
        end
    end
end

% Function to check if two points are close within a threshold
function result = isclose(pt1, pt2, threshold)
    result = norm(pt1 - pt2) < threshold;
end

% Function to update tracking data
function updateTrackingData(bbox, depth, depthOffset, depthScale, faceCoordMatrix)
    centerX = bbox(1) + bbox(3) / 2;
    centerY = bbox(2) + bbox(4) / 2;
    depthValue = depth(round(centerY), round(centerX));
    distance = (depthValue - depthOffset) * depthScale;
    faceCoordMatrix = [faceCoordMatrix; centerX, centerY, distance];
end

% close all;
