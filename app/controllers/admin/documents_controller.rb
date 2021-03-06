class Admin::DocumentsController < AdminController
  before_filter :fetch_document, only: [:edit, :update, :destroy]
  before_filter :ensure_editor!, only: [:destroy]

  def unpublished
    logger.ap params
    if ( current_user.is_editor && current_user.is_admin )
      @documents = Document.all
    else
      @documents = Document.where(
        contributor_id: current_user.self_and_descendant_ids
      )
    end

    # This doesn't look like it's used anywhere
    # @unpublished_documents = @documents.where(published: 'false')
    respond_to do |format|
      format.html
      format.json { render json: response_as_json(false) }
    end
  end

  def published
    if ( current_user.is_editor && current_user.is_admin )
      @documents = Document.all
    else
      @documents = Document.where(
        contributor_id: current_user.self_and_descendant_ids
      )
    end

    # This doesn't look like it's used anywhere
    # @published_documents = @documents.where(published: 'true')
    respond_to do |format|
      format.html
      format.json { render json: response_as_json(true) }
    end
  end

  def new
    @document = current_user.documents.build
    @document.build_body
  end

  def edit
    unless @document.processed
      flash[:error] = "Sorry, that document cannot be edited until after it has been processed by the system"
      redirect_to unpublished_admin_documents_path
    end
  end

  def create
    if permitted_params[:contributor_id]
      contributor = User.find(permitted_params[:contributor_id])
    else
      contributor = current_user
    end

    @document = contributor.documents.build permitted_params

    if @document.save
      @document.index!
      flash[:notice] = 'Document created successfully'
      if params[:create_and_continue]
        redirect_to new_admin_document_path
      elsif params[:create_and_edit]
        # BUG: I don't think this will ever work for a PDF upload because the PDF
        #   is guaranteed to *not* be processed when we redirect to the edit page,
        #   but the edit page will display an error message to the user that they
        #   cannot edit it until it's been processed. That means this will only
        #   work if document_style == 'noscan'.
        redirect_to edit_admin_document_path @document
      else
        redirect_to unpublished_admin_documents_path
      end
    else
      flash[:error] = @document.errors.full_messages.to_sentence
      render :new
    end
  end

  def update
    prev_state = @document.published
    if @document.update permitted_params
      flash[:notice] = 'Document updated successfully'
      if current_user.requires_approval?
        @document.update! published: false
      end
      @document.index!
      DocumentTypeCountWorker.perform_async
      if params[:create_and_continue]
        redirect_to new_admin_document_path
      elsif params[:create_and_edit]
        redirect_to edit_admin_document_path @document
      else
        # if we unpublish a document, we want to stay on the
        # unpublished view so that we can unpublish another if needed
        if @document.published != prev_state
          if @document.published
            redirect_to unpublished_admin_documents_path
          else
            redirect_to published_admin_documents_path
          end
        else
          redirect_to published_admin_documents_path
        end
      end
    else
      flash[:error] = @document.errors.full_messages.to_sentence
      render :edit
    end
  end

  def destroy
    if @document.destroy
      flash[:notice] = 'Document deleted successfully'
    else
      flash[:error] = 'An error occurred while trying to delete that Document'
    end
    redirect_to published_admin_documents_path
  end

  protected

  def permitted_params
    # TODO: Unpermitted parameters: alternate_editors, alternate_translators, alternate_years
    whitelist = [:title, :volume_count, :document_type_id, :pdf, :language_id,
                 :gregorian_year, :gregorian_month, :gregorian_day,
                 :source_name, :source_url, :author, :translators, :editors,
                 :publisher, :publisher_location, :alternate_titles,
                 :alternate_authors, :featured_position, :reference_type_id,
                 :permission_giver, :document_style, :summary, :citation,
                 region_ids: [], theme_ids: [], topic_ids: [], tag_ids: [],
                 referenced_document_ids: [], era_ids: [],
                 body_attributes: [:id, :text], pages_attributes: [
                   :id, body_attributes: [:id, :text, :hybrid_text]
                 ]]
    if current_user.is_editor
      whitelist << :contributor_id
    end
    unless current_user.requires_approval?
      whitelist << :published
    end
    params.require(:document).permit(*whitelist)
  end

  def fetch_document
    @document = Document.find params[:id]
    unless current_user.is_editor || current_user.self_and_descendant_ids.include?(@document.contributor.id)
      flash[:alert] = "Sorry, but you must be an editor or the owner of that document to do this"
      redirect_to :back
    end
  end

  def response_as_json(pstatus)
    {
      sEcho: params[:sEcho].to_i,
      iTotalRecords: Document.where(published: pstatus).count,
      iTotalDisplayRecords: fetch_documents(pstatus).count,
      aaData: data(pstatus)
    }
  end

  def data(pstatus)
    fetch_documents(pstatus).map do |document|
      row = [
        document.title,
        document.publisher,
        document.tags.pluck(:name).join(', '),
        document.topics.pluck(:name).join(', '),
        document.contributor.name,
        document.language.name,
        document.regions.pluck(:name).join(', '),
        document.updated_at.strftime("%b %e, %Y"),
        render_to_string(partial:"/admin/documents/datatable_controls.html.slim", :locals => {document:document}, layout: false )
      ]
      row
    end
  end

  def fetch_documents(pstatus)
    documents = Document.where(published: pstatus)

    if params[:sSearch].present?
      ids = documents.search do
        fulltext params[:sSearch]
      end.results.map(&:id)
      documents = Document.where(published: pstatus, id: ids)
    end
    documents = documents.page(page).per_page(per_page)

    order_documents(documents)
  end

  def page
    params[:iDisplayStart].to_i/per_page + 1
  end

  def per_page
    params[:iDisplayLength].to_i > 0 ? params[:iDisplayLength].to_i : 10
  end

  def order_documents(docs)
    columns = %w[title publisher tags topics contributor language regions updated_at]
    col = columns[params[:iSortCol_0].to_i]
    case col
    when "title","publisher", "updated_at" then docs.order("#{col} #{sort_direction}")
    when "topics" then docs.joins(:topics).order("topics.name #{sort_direction}")
    when "tags" then docs.includes(:tags).order("tags.name #{sort_direction}")
    when "contributor" then docs.joins(:contributor).order("users.last_name #{sort_direction}")
    when "language" then docs.joins(:language).order("languages.name #{sort_direction}")
    when "regions" then docs.joins(:regions).order("regions.name #{sort_direction}")
    end
  end

  def sort_direction
    params[:sSortDir_0] == "desc" ? "desc" : "asc"
  end
end
