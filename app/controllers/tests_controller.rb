class TestsController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :authorize!, except: [:index, :new, :create, :bulk_move, :bulk_destroy]

  def index
    @tests = Test.all
  end

  def show
    respond_to do |format|
      format.html do
        gon.test = @test
        gon.resultLabelTexts = @test.result_label_texts
        gon.resultLabels = @test.result_labels_or_default
      end
      format.csv do
        encode = "UTF-8"
        encode = "Windows-31J" if I18n.locale == :ja
        csv_data = render_to_string.encode(encode, :invalid => :replace, :undef => :replace)
        send_data csv_data, type: "text/csv; charset=#{encode}", filename: "testcase.csv"
      end
    end
  end

  def new
    @test = Test.new

    # Duplicate test
    if source = Test.find_by(slug: params[:source])
      @test.project_id = source.project_id
      @test.title = source.title
      @test.source = source.slug

      source.set_markdown(false)
      @test.markdown = source.markdown
    end
  end

  def edit
    forbidden_error unless @test.user  # Owner unknown
    
    @test.set_markdown(true)
  end

  def create
    @test = current_user.tests.build(test_params)

    team = Team.find_by(name: params[:test][:team_name])
    project = team.projects.find_by(name: params[:test][:project_name]) if team && team.authorized?(current_user)
    @test.project_id = project.id if project

    # Duplicate test
    if source = Test.find_by(slug: @test.source)
      @test.description = source.description
      @test.result_labels = source.result_labels
    end

    if @test.save
      @test.make_testcase
    end
  end

  def update
    @test.updated_at = Time.now
    if @test.update(test_params)
      @test.make_testcase if @test.markdown
    end
  end

  def destroy
    team = view_context.current_team
    project = view_context.current_project

    @test.destroy
    if project
      redirect_to team_project_path(team_name: team.name, project_name: project.name), notice: t("tests.messages.destroy")
    else
      redirect_to dashboard_path, notice: t("tests.messages.destroy")
    end
  end

  def description
  end

  def result_label
  end

  def update_result_label
    @test.result_labels = nil
    if params[:test][:use_default] == "0"
      # Use default label
      keys = params[:test][:result_label_texts]
      vals = params[:test][:result_label_colors]
      hash = Hash[*keys.zip(vals).flatten]
      @test.result_labels = hash
    end
    @test.save
  end

  def move
    @teams = current_user.teams
  end

  def bulk_move
    if params[:project].blank?
      project_id = nil  # Unset project
    else
      return unless project = Project.find(params[:project])  # Project not found
      return unless project.team.authorized?(current_user)  # Forbidden error
      project_id = project.id  # Move to project
    end

    params[:tests].each do |i|
      test = Test.find(i)
      next if test.project.nil? && test.user != current_user
      next unless test.authorized?(current_user)
      test.update_column(:project_id, project_id)
    end
  end

  def bulk_destroy
    params[:tests].each do |i|
      test = Test.find(i)
      next if test.project.nil? && test.user != current_user
      next unless test.authorized?(current_user)
      test.destroy
    end
  end

  def user_association
    @test.update(user_id: current_user.id) unless @test.user
    redirect_to @test
  end

  private
    def set_test
      @test = Test.find_by(slug: params[:slug])
      routing_error if @test.nil?
    end

    def authorize!
      @test || set_test
      if @project = @test.project
        team = @project.team || Team.find_by(name: params[:team_name])
        forbidden_error unless team.authorized?(current_user)
      end
    end

    def test_params
      params.require(:test).permit(:title, :description, :project_id, :markdown, :source)
    end
end