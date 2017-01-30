Feature: As an Admin
  So that I can use the exisiting Mailchimp system to share information with members
  I need to be able to export member names and emails to a csv file


  Background:
    Given the following users exists
      | email                       | admin |
      | emma@happymutts.com         |       |
      | wils@woof.com               |       |
      | admin@shf.se                | true  |


    And the following regions exist:
      | name         |
      | Stockholm    |
      | Västerbotten |
      | Norrbotten   |


    # old_region is currently required so that company_complete? is true
    And the following companies exist:
      | name                 | company_number | email                 | region       | old_region |
      | Happy Mutts          | 2120000142     | woof@happymutts.com   | Stockholm    | Sweden     |
      | WOOF                 | 5569467466     | woof@woof.com         | Västerbotten | Sweden     |

    And the following applications exist:
      | first_name | last_name   | user_email          | company_number | state    |
      | Emma       | Emmasdottir | emma@happymutts.com | 2120000142     | accepted |
      | Wils       | Wilson      | wils@woof.com       | 5569467466     | new      |


  Scenario: Visitor can't export
    Given I am Logged out
    When I am on the list applications page
    Then I should see t("errors.not_permitted")


  Scenario: User can't export
    Given I am logged in as "new@kats.com"
    When I am on the list applications page
    Then I should see t("errors.not_permitted")


  Scenario: Member can't export
    Given I am logged in as "emma@happymutts.com"
    When I am on the list applications page
    Then I should see t("errors.not_permitted")

  Scenario: Admin can export
    Given I am logged in as "admin@shf.se"
    And I am on the "landing" page
    When I click on t("admin.index.export") button
    And I am on the "landing" page
    Then I should see t("admin.export_ansokan_csv.success")


  Scenario: Export is on the admin page, not list all applications page
    Given I am logged in as "admin@shf.se"
    And I am on the list applications page
    Then I should not see button t("admin.index.export")
