Then(/^I should be on the landing page$/) do
  expect(current_path).to eq root_path
end

And(/^I should see "([^"]*)"$/) do |content|
  expect(page).to have_content content
end

Then(/^I should see:$/) do |table|
  table.hashes.each do |hash|
    expect(page).to have_content hash[:content]
  end
end

And(/^"([^"]*)" should be set in "([^"]*)"$/) do |status, list|
  dropdown = page.find("##{list}")
  selected_option = dropdown.find('option[selected]').text
  expect(selected_option).to eql status
end
