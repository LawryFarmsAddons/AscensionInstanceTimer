-- InstanceCounter.lua

-- Localize API functions for performance and safety
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local time = time
local date = date
local tinsert = tinsert
local tremove = tremove
local CreateFrame = CreateFrame
local GetMouseFocus = GetMouseFocus

-- SavedVariables (loaded from InstanceCounter.toc)
InstanceCounterDB = InstanceCounterDB or { history = {} }

-- Local variables
local sessionCount = 0
local wasInInstance = false
local currentInstanceID = nil
local selectedInstances = {} -- Track selected instances for deletion

-- Function to check if instance is from Random Dungeon Finder
function IsRDFInstance(instanceName, difficultyID)
    if not instanceName then return false end
    local rdfKeywords = {
        ["Random"] = true,
        ["RDF"] = true,
    }
    for keyword in pairs(rdfKeywords) do
        if string.find(instanceName, keyword, 1, true) then
            return true
        end
    end
    return false
end

-- Function to get color based on elapsed time
local function GetTimeColor(entryTime)
    local currentTime = time()
    local elapsed = currentTime - entryTime
    local elapsedMinutes = elapsed / 60
    
    if elapsedMinutes < 20 then
        return 1, 0.6, 0, 1
    elseif elapsedMinutes < 40 then
        return 1, 1, 0, 1
    elseif elapsedMinutes < 60 then
        return 0.3, 1, 0.3, 1
    else
        return 0.5, 0.5, 0.5, 1
    end
end

-- Function to check if instance is approved
local function IsInstanceApproved(entry)
    return entry.approved == true
end

-- Function to approve an instance
InstanceCounter_ApproveInstance = function(index)
    if InstanceCounterDB.history[index] then
        InstanceCounterDB.history[index].approved = true
        InstanceCounter_UpdateDisplay()
    end
end

-- Function to remove an instance
InstanceCounter_RemoveInstance = function(index)
    tremove(InstanceCounterDB.history, index)
    InstanceCounter_UpdateDisplay()
end

-- Function to delete selected instances
InstanceCounter_DeleteSelectedInstances = function()
    -- Delete from highest index to lowest to avoid shifting issues
    local sortedIndices = {}
    for index, _ in pairs(selectedInstances) do
        table.insert(sortedIndices, index)
    end
    table.sort(sortedIndices, function(a, b) return a > b end)
    
    for _, index in ipairs(sortedIndices) do
        tremove(InstanceCounterDB.history, index)
        selectedInstances[index] = nil
    end
    
    InstanceCounter_UpdateDisplay()
end

-- Function to toggle instance selection
InstanceCounter_ToggleInstanceSelection = function(index)
    if selectedInstances[index] then
        selectedInstances[index] = nil
    else
        selectedInstances[index] = true
    end
    InstanceCounter_UpdateDisplay()
end

-- Function to update the display
InstanceCounter_UpdateDisplay = function()
    -- Get the main frame and its children
    local mainFrame = _G["InstanceCounterMainFrame"]
    if not mainFrame then return end

    -- Update or create session text
    local sessionText = mainFrame.sessionText
    if not sessionText then
        sessionText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sessionText:SetPoint("TOP", mainFrame.TitleText or mainFrame, "BOTTOM", 0, -4)
        mainFrame.sessionText = sessionText
    end
    sessionText:SetText(string.format("Session: %d", sessionCount))

    -- Update or create current instance ID text
    local instanceIDText = mainFrame.instanceIDText
    if not instanceIDText then
        instanceIDText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        instanceIDText:SetPoint("TOP", sessionText, "BOTTOM", 0, -4)
        mainFrame.instanceIDText = instanceIDText
    end
    if currentInstanceID then
        instanceIDText:SetText(string.format("Current Instance ID: %d", currentInstanceID))
        instanceIDText:Show()
    else
        instanceIDText:SetText("")
        instanceIDText:Hide()
    end

    -- Update or create timer text
    local timerText = mainFrame.timerText
    if not timerText then
        timerText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        timerText:SetPoint("TOP", instanceIDText, "BOTTOM", 0, -4)
        mainFrame.timerText = timerText
    end

    -- Update timer display
    if #InstanceCounterDB.history >= 5 then
        local fifthEntry = InstanceCounterDB.history[#InstanceCounterDB.history - 4]; -- 5th from last
        local entryTime = fifthEntry.time
        local currentTime = time()
        local elapsed = currentTime - entryTime
        local remaining = 3600 - elapsed; -- 1 hour in seconds
        
        if remaining > 0 then
            local hours = math.floor(remaining / 3600)
            local minutes = math.floor((remaining % 3600) / 60)
            local seconds = remaining % 60
            timerText:SetText(string.format("Timer: %02d:%02d:%02d", hours, minutes, seconds))
            timerText:SetTextColor(1, 0.3, 0.3) -- Red color
        else
            timerText:SetText("Timer: You may enter a new instance")
            timerText:SetTextColor(0.3, 1, 0.3) -- Green color
        end
    else
        timerText:SetText("Timer: Need 5 instances")
        timerText:SetTextColor(0.6, 0.6, 0.6) -- Gray color
    end

    -- Update history list
    local scrollChild = _G["InstanceCounterScrollChildFrame"]
    if not scrollChild then return end

    local lines = InstanceCounterLines or {}
    InstanceCounterLines = lines

    local height = 0
    for i, entry in ipairs(InstanceCounterDB.history) do
        local line = lines[i]
        if not line then
            -- Create a frame to hold the checkbox and text
            line = CreateFrame("Frame", "InstanceCounterLine"..i, scrollChild)
            lines[i] = line
            if i == 1 then
                line:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
            else
                line:SetPoint("TOPLEFT", lines[i-1], "BOTTOMLEFT", 0, -2)
            end
            
            -- Set size
            line:SetWidth(220)
            line:SetHeight(16)
            
            -- Create checkbox
            local checkbox = CreateFrame("CheckButton", "InstanceCounterCheckbox"..i, line, "UICheckButtonTemplate")
            checkbox:SetPoint("LEFT", 0, 0)
            checkbox:SetSize(16, 16)
            checkbox:SetScript("OnClick", function()
                InstanceCounter_ToggleInstanceSelection(i)
            end)
            line.checkbox = checkbox
            
            -- Create text string
            local text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            line.text = text
        end
        
        -- Skip RDF instances from display in main window
        if IsRDFInstance(entry.name, entry.difficultyID) then
            line:Hide()
        else
            local timeString = date("%H:%M:%S", entry.time)
            local displayText = string.format("%d. [%s] %s", i, timeString, entry.name or "Unknown")
            
            -- Apply color coding based on time elapsed
            local r, g, b, a = GetTimeColor(entry.time)
            
            -- Add approval indicator if approved
            if IsInstanceApproved(entry) then
                displayText = displayText .. " ✓"
            end
            
            line.text:SetText(displayText)
            line.text:SetTextColor(r, g, b, a)
            
            -- Set checkbox state
            line.checkbox:SetChecked(selectedInstances[i] or false)
            
            line:Show()
        end
        height = height + line:GetHeight() + 2
    end
    -- Hide extra lines
    for i = #InstanceCounterDB.history + 1, #lines do
        lines[i]:Hide()
    end
    scrollChild:SetHeight(height)
end

-- Function to clear instances
InstanceCounter_ClearInstances = function()
    sessionCount = 0
    InstanceCounterDB.history = {}
    selectedInstances = {}
    InstanceCounter_UpdateDisplay()
end

-- Event handler
InstanceCounter_OnEvent = function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local inInstance, instanceType = IsInInstance()
        if inInstance and not wasInInstance then
            -- Just entered an instance
            local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
            -- Only count if this instanceID is different from the current instance we're tracking
            if currentInstanceID ~= instanceID then
                sessionCount = sessionCount + 1
                currentInstanceID = instanceID
                tinsert(InstanceCounterDB.history, {
                    time = time(),
                    name = instanceName,
                    instanceID = instanceID,
                })
                InstanceCounter_UpdateDisplay()
            end
        elseif not inInstance and wasInInstance then
            -- Just left an instance
            currentInstanceID = nil
        end
        wasInInstance = inInstance
    end
end

-- Create event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", InstanceCounter_OnEvent)

-- Update display when main frame is shown
-- Handled by OnUpdate script in XML