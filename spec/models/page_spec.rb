require 'rails_helper'

# == Schema Information
#
# Table name: pages
#
#  id          :integer          not null, primary key
#  image       :string(255)
#  document_id :integer
#  number      :integer
#  width       :integer
#  height      :integer
#

describe Page do
  it { should respond_to :image }
  it { should validate_numericality_of(:number).is_greater_than(0) }
  it { should validate_numericality_of(:width) }
  it { should validate_numericality_of(:height) }
  it { should have_one(:body).dependent(:destroy) }
  it { should belong_to :document }
  it { should accept_nested_attributes_for :body }
end
