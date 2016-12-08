Feature: As a member
  So that visitors can see if my company offers services they might be interested in
  I need to be able to set a page that displays information about my company

  PT:  https://www.pivotaltracker.com/story/show/133081453

  Background:
    Given the following users exists
      | email              | admin | is_member |
      | admin@shf.se       | true  | true      |
      | emma@happymutts.se |       | true      |

    And the following companies exist:
      | name                 | company_number | email                  |
      | Happy Mutts          | 5562252998     | emma@happymutts.se    |

    And the following business categories exist
      | name  |
      | Rehab |

    And the following applications exist:
      | first_name | user_email         | company_number | status   | category_name |
      | Emma       | emma@happymutts.se | 5562252998     | Godkänd | Rehab         |


  Scenario: Member goes to company page after membership approval
    Given I am logged in as "emma@happymutts.se"
    # we need to do user find by email and visit their particular company application
    And I am on the "edit my company" page for "emma@happymutts.se"
    And I fill in the form with data :
      | Företagsnamn  | Gata           | Post nr | Ort    | Verksamhetslän | Email                | Webbsida                  |
      | Happy Mutts   | Ålstensgatan 4 | 123 45  | Bromma | Stockholm      | kicki@gladajyckar.se | http://www.gladajyckar.se |
    And I click on "Submit"
    Then I should see "Företaget har uppdaterats."
    And I should see "Happy Mutts"
    And I should see "123 45"
    And I should see "Bromma"

  Scenario: Another tries to edit your company page (gets rerouted)
    Given I am logged in as "emma@happymutts.se"
    #And I am on the "edit my company" page for "emma@happymutts.se"
    And I am on the "edit my company" page
    And I fill in the form with data :
      | Företagsnamn | Org nr     | Gata           | Post nr | Ort    | Verksamhetslän | Email                | Webbsida                  |
      | Happy Mutts  | 5562252998 | Ålstensgatan 4 | 123 45  | Bromma | Stockholm      | kicki@gladajyckar.se | http://www.gladajyckar.se |
    And I click on "Submit"
    And I am Logged out
    And I am logged in as "applicant_2@random.com"
    And I am on the "edit my company" page for "emma@happymutts.se"
    Then I should be on the landing page
    And I should see "Du har inte behörighet att göra detta."


  Scenario: User tries to go do company page (gets rerouted)
    Given I am logged in as "applicant_2@random.com"
    And I am on the "edit my company" page for "emma@happymutts.se"
    Then I should be on the landing page
    And I should see "Du har inte behörighet att göra detta."


